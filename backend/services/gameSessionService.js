const crypto = require('crypto');
const { generatePuzzle } = require('./sudokuGenerator');
const { isBoardComplete } = require('./sudokuValidator');

const sessions = new Map();
const userSessions = new Map();
const SESSION_TIMEOUT_MS = 15 * 60 * 1000;

function generateSeed() {
  return crypto.randomInt(100000, 1000000);
}

function cloneBoard(board) {
  return board.map((row) => [...row]);
}

function createSession(player1Id, player2Id, options = {}) {
  const gameId = crypto.randomUUID();
  const seed = generateSeed();
  const { puzzle, solution } = generatePuzzle(seed);

  const playersMeta = options.playersMeta || {
    [player1Id]: { userId: player1Id, username: player1Id, rating: 1200 },
    [player2Id]: { userId: player2Id, username: player2Id, rating: 1200 },
  };

  sessions.set(gameId, {
    status: 'active',
    isBotMatch: options.isBotMatch === true,
    seed,
    puzzle,
    solution,
    players: [player1Id, player2Id],
    playersMeta,
    playerSockets: {
      [player1Id]: null,
      [player2Id]: null,
    },
    playerBoards: {
      [player1Id]: cloneBoard(puzzle),
      [player2Id]: cloneBoard(puzzle),
    },
    startTime: Date.now(),
    progress: {
      [player1Id]: { filledCells: 0, mistakes: 0, completed: false },
      [player2Id]: { filledCells: 0, mistakes: 0, completed: false },
    },
  });

  userSessions.set(player1Id, gameId);
  userSessions.set(player2Id, gameId);

  return { gameId, puzzle, status: 'active' };
}

function getSession(gameId) {
  return sessions.get(gameId);
}

function getUserSession(userId) {
  return userSessions.get(userId);
}

function setPlayerSocket(gameId, userId, socketId) {
  const session = sessions.get(gameId);
  if (!session || !session.playerSockets || !session.playerSockets[userId] && session.playerSockets[userId] !== null) {
    return false;
  }

  session.playerSockets[userId] = socketId;
  return true;
}

function isBoardShapeValid(board) {
  return (
    Array.isArray(board)
    && board.length === 9
    && board.every((row) => Array.isArray(row) && row.length === 9)
  );
}

function updateProgress(gameId, playerId, data) {
  const session = sessions.get(gameId);
  if (!session) return null;
  if (!session.progress[playerId]) return null;

  if (data.filledCells !== undefined) {
    if (!Number.isInteger(data.filledCells) || data.filledCells < 0 || data.filledCells > 81) {
      return { error: 'Invalid filledCells' };
    }
  }

  if (data.mistakes !== undefined) {
    if (!Number.isInteger(data.mistakes) || data.mistakes < 0 || data.mistakes > 3) {
      return { error: 'Invalid mistakes' };
    }
  }

  if (data.board !== undefined) {
    if (!isBoardShapeValid(data.board)) {
      return { error: 'Invalid board payload' };
    }

    if (session.playerBoards && session.playerBoards[playerId]) {
      session.playerBoards[playerId] = cloneBoard(data.board);
    }
  }

  if (data.completed === true) {
    if (!data.board || !isBoardShapeValid(data.board)) {
      return { error: 'Invalid board payload' };
    }

    const validSolution = isBoardComplete(data.board, session.solution);
    if (!validSolution) {
      return { error: 'Invalid solution' };
    }
  }

  const progressUpdate = {};
  if (data.filledCells !== undefined) progressUpdate.filledCells = data.filledCells;
  if (data.mistakes !== undefined) progressUpdate.mistakes = data.mistakes;
  if (data.completed !== undefined) progressUpdate.completed = data.completed;

  session.progress[playerId] = {
    ...session.progress[playerId],
    ...progressUpdate,
  };

  // Server-authoritative completion: only finish after validated board.
  if (data.completed === true) {
    return finishSession(gameId, playerId);
  }

  return session;
}

function finishSession(gameId, winnerId) {
  const session = sessions.get(gameId);
  if (!session) return null;

  const duration = Math.floor((Date.now() - session.startTime) / 1000);
  const suspiciousSolve = duration < 20;
  const loserId = session.players.find((playerId) => playerId !== winnerId) || null;

  if (suspiciousSolve) {
    console.warn(`Suspicious solve detected for player ${winnerId} in ${duration}s`);
  }

  for (const playerId of session.players) {
    userSessions.delete(playerId);
  }

  sessions.delete(gameId);

  return {
    ...session,
    status: 'finished',
    winnerId,
    loserId,
    duration,
    suspiciousSolve,
  };
}

const cleanupInterval = setInterval(() => {
  const now = Date.now();

  for (const [gameId, session] of sessions) {
    if (now - session.startTime > SESSION_TIMEOUT_MS) {
      for (const playerId of session.players) {
        userSessions.delete(playerId);
      }
      sessions.delete(gameId);
    }
  }
}, 60 * 1000);

if (typeof cleanupInterval.unref === 'function') {
  cleanupInterval.unref();
}

module.exports = {
  sessions,
  userSessions,
  generateSeed,
  createSession,
  getSession,
  getUserSession,
  setPlayerSocket,
  updateProgress,
  finishSession,
};
