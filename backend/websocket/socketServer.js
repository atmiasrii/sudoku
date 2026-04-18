const {
  createSession,
  getSession,
  getUserSession,
  setPlayerSocket,
  updateProgress,
  finishSession,
} = require('../services/gameSessionService');
const { storeMatchResult } = require('../services/gameService');
const { getUserById, updateUserRating } = require('../services/userService');
const {
  addToQueue,
  findMatch,
  removeFromQueue,
  getQueuedPlayer,
} = require('../services/matchmakingService');
const { calculateElo } = require('../services/eloService');
const {
  logMatch,
  logSuspicious,
  logDisconnect,
  logQueue,
} = require('../services/logService');

const activeUsers = new Set();
const matchingUsers = new Set();
const disconnectTimers = new Map();
const queueFallbackTimers = new Map();
const botProgressIntervals = new Map();
const botFinishTimers = new Map();
const DISCONNECT_GRACE_MS = Number(process.env.DISCONNECT_GRACE_MS) || 10000;
const BOT_MATCH_WAIT_MS = 5000;

function isBotId(userId) {
  return typeof userId === 'string' && userId.startsWith('bot_');
}

function clearQueueFallbackTimer(userId) {
  const timer = queueFallbackTimers.get(userId);
  if (!timer) return;
  clearTimeout(timer);
  queueFallbackTimers.delete(userId);
}

function clearBotSimulation(gameId) {
  const progressTimer = botProgressIntervals.get(gameId);
  if (progressTimer) {
    clearInterval(progressTimer);
    botProgressIntervals.delete(gameId);
  }

  const finishTimer = botFinishTimers.get(gameId);
  if (finishTimer) {
    clearTimeout(finishTimer);
    botFinishTimers.delete(gameId);
  }
}

function emitBotProgress(io, gameId, botId) {
  const session = getSession(gameId);
  if (!session || !session.progress?.[botId]) {
    clearBotSimulation(gameId);
    return;
  }

  const humanId = session.players.find((id) => id !== botId);
  if (!humanId) {
    clearBotSimulation(gameId);
    return;
  }

  const current = session.progress[botId] || { filledCells: 0, mistakes: 0 };
  const nextFilled = Math.min(80, current.filledCells + Math.floor(Math.random() * 4));
  const nextMistakes = Math.min(2, current.mistakes + (Math.random() < 0.2 ? 1 : 0));
  const result = updateProgress(gameId, botId, {
    filledCells: nextFilled,
    mistakes: nextMistakes,
    completed: false,
  });

  if (!result) {
    clearBotSimulation(gameId);
    return;
  }

  io.to(gameId).emit('progress_update', {
    gameId,
    playerId: botId,
    finished: false,
    session: toPublicSession(gameId, result),
  });
}

function startBotSimulation(io, gameId, botId) {
  clearBotSimulation(gameId);

  const progressInterval = setInterval(() => {
    emitBotProgress(io, gameId, botId);
  }, 2500);

  botProgressIntervals.set(gameId, progressInterval);

  const finishDelayMs = 60000 + Math.floor(Math.random() * 45000);
  const finishTimer = setTimeout(() => {
    const session = getSession(gameId);
    if (!session || !session.progress?.[botId]) {
      clearBotSimulation(gameId);
      return;
    }

    const finishedResult = finishSession(gameId, botId);
    if (!finishedResult) {
      clearBotSimulation(gameId);
      return;
    }

    finalizeMatch(io, gameId, finishedResult, 'bot_completed').catch((error) => {
      console.error('Failed to finalize bot-ended match:', error.message);
    });
  }, finishDelayMs);

  botFinishTimers.set(gameId, finishTimer);
}

function scheduleBotFallback(io, queuedPlayer) {
  clearQueueFallbackTimer(queuedPlayer.userId);

  const timer = setTimeout(() => {
    queueFallbackTimers.delete(queuedPlayer.userId);

    const liveQueuedPlayer = getQueuedPlayer(queuedPlayer.userId);
    if (!liveQueuedPlayer) return;
    if (matchingUsers.has(queuedPlayer.userId)) return;

    const liveSocket = io.sockets.sockets.get(liveQueuedPlayer.socketId);
    if (!liveSocket) {
      removeFromQueue(liveQueuedPlayer.userId);
      activeUsers.delete(liveQueuedPlayer.userId);
      return;
    }

    matchingUsers.add(liveQueuedPlayer.userId);

    try {
      removeFromQueue(liveQueuedPlayer.userId);

      const botId = `bot_${Math.random().toString(36).slice(2, 10)}`;
      const playerId = liveQueuedPlayer.userId;

      const playersMeta = {
        [botId]: {
          userId: botId,
          username: 'Sudoku Bot',
          rating: Math.max(900, Math.min(2200, liveQueuedPlayer.rating + 25)),
        },
        [playerId]: {
          userId: playerId,
          username: liveQueuedPlayer.username || playerId,
          rating: liveQueuedPlayer.rating,
        },
      };

      const { gameId, puzzle } = createSession(botId, playerId, {
        playersMeta,
        isBotMatch: true,
      });

      liveSocket.data.userId = playerId;
      liveSocket.data.gameId = gameId;
      setPlayerSocket(gameId, playerId, liveSocket.id);

      liveSocket.join(gameId);
      liveSocket.emit('match_found', {
        gameId,
        puzzle,
        playersMeta,
      });

      const matchedAt = Date.now();
      const playerWait = Math.max(0, Math.floor((matchedAt - (liveQueuedPlayer.joinedAt || matchedAt)) / 1000));
      logQueue({
        user_id: playerId,
        joined_at: new Date(liveQueuedPlayer.joinedAt || matchedAt).toISOString(),
        matched_at: new Date(matchedAt).toISOString(),
        wait_time: playerWait,
      }).catch((error) => {
        console.error('Failed to write bot queue match log:', error.message);
      });

      startBotSimulation(io, gameId, botId);
    } finally {
      matchingUsers.delete(liveQueuedPlayer.userId);
    }
  }, BOT_MATCH_WAIT_MS);

  queueFallbackTimers.set(queuedPlayer.userId, timer);
}

function isProgressValueInRange(value, min, max) {
  return Number.isInteger(value) && value >= min && value <= max;
}

async function persistMatchResult(sessionResult) {
  if (!sessionResult || !Array.isArray(sessionResult.players) || sessionResult.players.length !== 2) {
    return null;
  }

  if (sessionResult.isBotMatch || sessionResult.players.some((playerId) => isBotId(playerId))) {
    return null;
  }

  const [player1Id, player2Id] = sessionResult.players;
  const winnerMistakes = sessionResult.progress?.[sessionResult.winnerId]?.mistakes || 0;

  return storeMatchResult({
    seed: sessionResult.seed,
    player1_id: player1Id,
    player2_id: player2Id,
    winner_id: sessionResult.winnerId,
    duration: sessionResult.duration || 0,
    mistakes: winnerMistakes,
  });
}

async function calculateAndPersistRatings(sessionResult) {
  if (!sessionResult || !Array.isArray(sessionResult.players) || sessionResult.players.length !== 2) {
    return null;
  }

  if (sessionResult.isBotMatch || sessionResult.players.some((playerId) => isBotId(playerId))) {
    return null;
  }

  const [player1Id, player2Id] = sessionResult.players;
  const winnerId = sessionResult.winnerId;

  const [player1, player2] = await Promise.all([
    getUserById(player1Id),
    getUserById(player2Id),
  ]);

  const oldRating1 = Number(player1?.rating ?? 1200);
  const oldRating2 = Number(player2?.rating ?? 1200);

  const player1Score = winnerId === player1Id ? 1 : 0;
  const player2Score = winnerId === player2Id ? 1 : 0;

  const newRating1 = calculateElo(oldRating1, oldRating2, player1Score);
  const newRating2 = calculateElo(oldRating2, oldRating1, player2Score);

  await Promise.all([
    updateUserRating(player1Id, newRating1),
    updateUserRating(player2Id, newRating2),
  ]);

  return {
    player1Id,
    player2Id,
    winnerId,
    loserId: sessionResult.loserId,
    ratings: {
      [player1Id]: newRating1,
      [player2Id]: newRating2,
    },
    previousRatings: {
      [player1Id]: oldRating1,
      [player2Id]: oldRating2,
    },
  };
}

async function finalizeMatch(io, gameId, sessionResult, reason) {
  let persistedMatch = null;
  let ratingUpdate = null;

  clearBotSimulation(gameId);

  for (const playerId of sessionResult.players || []) {
    const timer = disconnectTimers.get(playerId);
    if (timer) {
      clearTimeout(timer);
      disconnectTimers.delete(playerId);
    }
  }

  try {
    persistedMatch = await persistMatchResult(sessionResult);
  } catch (error) {
    console.error('Failed to persist match result:', error.message);
  }

  try {
    const [player1Id, player2Id] = sessionResult.players || [];
    await logMatch({
      game_id: gameId,
      player1_id: player1Id || null,
      player2_id: player2Id || null,
      winner_id: sessionResult.winnerId || null,
      loser_id: sessionResult.loserId || null,
      duration: sessionResult.duration || 0,
      reason,
    });
  } catch (error) {
    console.error('Failed to write match log:', error.message);
  }

  if (sessionResult.suspiciousSolve) {
    try {
      await logSuspicious({
        user_id: sessionResult.winnerId || null,
        game_id: gameId,
        reason: 'too_fast',
        details: {
          duration: sessionResult.duration || 0,
        },
      });
    } catch (error) {
      console.error('Failed to write suspicious solve log:', error.message);
    }
  }

  try {
    ratingUpdate = await calculateAndPersistRatings(sessionResult);
  } catch (error) {
    console.error('Failed to persist rating update:', error.message);
  }

  io.to(gameId).emit('game_end', {
    ...sessionResult,
    reason,
    persistedMatch,
    ratingUpdate,
  });

  if (ratingUpdate) {
    io.to(gameId).emit('rating_update', ratingUpdate);
  }

  await cleanupRoom(io, gameId);
}

async function cleanupRoom(io, gameId) {
  const socketsInRoom = await io.in(gameId).fetchSockets();
  for (const roomSocket of socketsInRoom) {
    if (roomSocket.data.userId) {
      activeUsers.delete(roomSocket.data.userId);
    }
    roomSocket.data.gameId = null;
  }

  io.in(gameId).socketsLeave(gameId);
}

function toPublicSession(gameId, session, forUserId = null) {
  if (!session) return null;

  return {
    gameId,
    status: session.status,
    puzzle: session.puzzle,
    progress: session.progress,
    players: session.players,
    playersMeta: session.playersMeta || {},
    board: forUserId && session.playerBoards ? session.playerBoards[forUserId] || null : null,
  };
}

function initializeSocketServer(io) {
  io.on('connection', (socket) => {
    socket.on('join_queue', async (payload = {}) => {
      const userId = typeof payload.userId === 'string' ? payload.userId : null;
      if (!userId) return;

      if (activeUsers.has(userId)) {
        return;
      }

      const activeGameId = getUserSession(userId);
      if (activeGameId && getSession(activeGameId)) {
        const activeSession = getSession(activeGameId);
        socket.emit('reconnect_required', toPublicSession(activeGameId, activeSession, userId));
        return;
      }

      let rating = 1200;
      let username = userId;
      try {
        // Always fetch the latest rating from DB at queue-join time.
        const user = await getUserById(userId);
        rating = Number(user?.rating ?? 1200);
        username = user?.username || userId;
      } catch (error) {
        console.error(`Failed to fetch rating for ${userId}:`, error.message);
      }

      socket.data.userId = userId;
      activeUsers.add(userId);

      const queuedPlayer = addToQueue({
        userId,
        rating,
        username,
        socketId: socket.id,
      });

      socket.data.queueJoinedAt = queuedPlayer.joinedAt;

      try {
        await logQueue({
          user_id: userId,
          joined_at: new Date(queuedPlayer.joinedAt).toISOString(),
          matched_at: null,
          wait_time: null,
        });
      } catch (error) {
        console.error('Failed to write queue join log:', error.message);
      }

      const opponent = findMatch(queuedPlayer);
      if (!opponent) {
        scheduleBotFallback(io, queuedPlayer);
        return;
      }

      if (opponent.userId === queuedPlayer.userId) {
        return;
      }

      if (matchingUsers.has(queuedPlayer.userId) || matchingUsers.has(opponent.userId)) {
        return;
      }

      matchingUsers.add(queuedPlayer.userId);
      matchingUsers.add(opponent.userId);

      try {
        const opponentSocket = io.sockets.sockets.get(opponent.socketId);
        if (!opponentSocket) {
          removeFromQueue(opponent.userId);
          activeUsers.delete(opponent.userId);
          return;
        }

        // Remove both players from queue immediately to avoid double-match races.
        clearQueueFallbackTimer(queuedPlayer.userId);
        clearQueueFallbackTimer(opponent.userId);
        removeFromQueue(queuedPlayer.userId);
        removeFromQueue(opponent.userId);

        const player1Id = opponent.userId;
        const player2Id = queuedPlayer.userId;
        const playersMeta = {
          [player1Id]: {
            userId: player1Id,
            username: opponent.username || player1Id,
            rating: opponent.rating,
          },
          [player2Id]: {
            userId: player2Id,
            username: queuedPlayer.username || player2Id,
            rating: queuedPlayer.rating,
          },
        };

        const { gameId, puzzle } = createSession(player1Id, player2Id, { playersMeta });

        opponentSocket.data.userId = player1Id;
        opponentSocket.data.gameId = gameId;
        socket.data.gameId = gameId;

        setPlayerSocket(gameId, player1Id, opponentSocket.id);
        setPlayerSocket(gameId, player2Id, socket.id);

        opponentSocket.join(gameId);
        socket.join(gameId);

        io.to(gameId).emit('match_found', {
          gameId,
          puzzle,
          playersMeta,
        });

        const matchedAt = Date.now();
        const player1Wait = Math.max(0, Math.floor((matchedAt - (opponent.joinedAt || matchedAt)) / 1000));
        const player2Wait = Math.max(0, Math.floor((matchedAt - (queuedPlayer.joinedAt || matchedAt)) / 1000));

        try {
          await logQueue({
            user_id: player1Id,
            joined_at: new Date(opponent.joinedAt || matchedAt).toISOString(),
            matched_at: new Date(matchedAt).toISOString(),
            wait_time: player1Wait,
          });

          await logQueue({
            user_id: player2Id,
            joined_at: new Date(queuedPlayer.joinedAt || matchedAt).toISOString(),
            matched_at: new Date(matchedAt).toISOString(),
            wait_time: player2Wait,
          });
        } catch (error) {
          console.error('Failed to write queue match log:', error.message);
        }
      } finally {
        matchingUsers.delete(queuedPlayer.userId);
        matchingUsers.delete(opponent.userId);
      }
    });

    socket.on('progress_update', async (payload = {}) => {
      const gameId = payload.gameId || socket.data.gameId;
      const playerId = payload.userId || socket.data.userId;

      if (!gameId || !playerId) return;

      const data = {};

      if (payload.filledCells !== undefined) {
        if (!isProgressValueInRange(payload.filledCells, 0, 81)) return;
        data.filledCells = payload.filledCells;
      }

      if (payload.mistakes !== undefined) {
        if (!isProgressValueInRange(payload.mistakes, 0, 3)) return;
        data.mistakes = payload.mistakes;
      }

      if (payload.completed !== undefined) {
        data.completed = payload.completed;
      }

      if (payload.board !== undefined) {
        data.board = payload.board;
      }

      const result = updateProgress(gameId, playerId, data);
      if (!result) return;

      if (result.error) {
        if (result.error === 'Invalid board payload' || result.error === 'Invalid solution') {
          try {
            await logSuspicious({
              user_id: playerId,
              game_id: gameId,
              reason: 'invalid_board',
              details: {
                message: result.error,
              },
            });
          } catch (error) {
            console.error('Failed to write invalid board log:', error.message);
          }
        }

        socket.emit('progress_rejected', {
          gameId,
          playerId,
          message: result.error,
        });
        return;
      }

      if (data.completed === true) {
        io.to(gameId).emit('progress_update', {
          gameId,
          playerId,
          finished: true,
          result,
        });

        await finalizeMatch(io, gameId, result, 'completed');
        return;
      }

      io.to(gameId).emit('progress_update', {
        gameId,
        playerId,
        finished: false,
        session: toPublicSession(gameId, result),
      });
    });

    socket.on('reconnect_game', ({ userId, gameId } = {}) => {
      if (!userId) return;

      const resolvedGameId = gameId || getUserSession(userId);
      if (!resolvedGameId) {
        socket.emit('game_state_error', { message: 'Game not found' });
        return;
      }

      const session = getSession(resolvedGameId);
      if (!session || !session.players.includes(userId)) {
        socket.emit('game_state_error', { message: 'Game not found' });
        return;
      }

      const timer = disconnectTimers.get(userId);
      if (timer) {
        clearTimeout(timer);
        disconnectTimers.delete(userId);
      }

      socket.data.userId = userId;
      socket.data.gameId = resolvedGameId;
      activeUsers.add(userId);
      setPlayerSocket(resolvedGameId, userId, socket.id);

      socket.join(resolvedGameId);

      logDisconnect({
        user_id: userId,
        game_id: resolvedGameId,
        type: 'reconnect',
      }).catch((error) => {
        console.error('Failed to write reconnect log:', error.message);
      });

      socket.emit('game_state', {
        ...toPublicSession(resolvedGameId, session, userId),
      });

      socket.to(resolvedGameId).emit('opponent_reconnected', {
        gameId: resolvedGameId,
        userId,
      });
    });

    socket.on('disconnect', () => {
      const { userId, gameId } = socket.data;

      if (userId) {
        removeFromQueue(userId);
        clearQueueFallbackTimer(userId);
      }

      if (userId) {
        activeUsers.delete(userId);
      }

      if (!gameId || !userId) return;

      const liveSession = getSession(gameId);
      if (!liveSession) return;

      setPlayerSocket(gameId, userId, null);

      const opponentId = liveSession.players.find((id) => id !== userId);
      socket.to(gameId).emit('opponent_disconnected', {
        gameId,
        userId,
      });

      logDisconnect({
        user_id: userId,
        game_id: gameId,
        type: 'disconnect',
      }).catch((error) => {
        console.error('Failed to write disconnect log:', error.message);
      });

      if (!opponentId) return;

      const previousTimer = disconnectTimers.get(userId);
      if (previousTimer) {
        clearTimeout(previousTimer);
      }

      const timer = setTimeout(() => {
        const sessionAfterGrace = getSession(gameId);
        if (!sessionAfterGrace) return;

        const playerSocketId = sessionAfterGrace.playerSockets?.[userId] || null;
        if (playerSocketId) return;

        const finishedResult = finishSession(gameId, opponentId);
        if (!finishedResult) return;

        finalizeMatch(io, gameId, finishedResult, 'opponent_disconnected').catch((error) => {
          console.error('Failed to finalize disconnect-ended match:', error.message);
        });
      }, DISCONNECT_GRACE_MS);

      disconnectTimers.set(userId, timer);
    });
  });
}

module.exports = {
  initializeSocketServer,
};
