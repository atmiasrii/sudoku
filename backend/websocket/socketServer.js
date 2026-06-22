const {
  createSession,
  getSession,
  getUserSession,
  setPlayerSocket,
  updateProgress,
  finishSession,
} = require('../services/gameSessionService');
const { storeMatchResult } = require('../services/gameService');
const { getUserById, incrementUserRating, getBotPool } = require('../services/userService');
const {
  addToQueue,
  findMatch,
  removeFromQueue,
  getQueuedPlayer,
  getQueueSnapshot,
} = require('../services/matchmakingService');
const { calculateElo } = require('../services/eloService');
const {
  logMatch,
  logSuspicious,
  logDisconnect,
  logQueue,
} = require('../services/logService');
const { socketAuth } = require('../middleware/auth');
const { withTimeout } = require('../utils/withTimeout');

const activeUsers = new Set();
const matchingUsers = new Set();
const disconnectTimers = new Map();
const queueFallbackTimers = new Map();
const botProgressIntervals = new Map();
const botFinishTimers = new Map();
// Per-bot-match simulation plan: how fast this bot "solves" and whether it is
// fated to bust on mistakes. Keyed by gameId.
const botPlans = new Map();
const DISCONNECT_GRACE_MS = Number(process.env.DISCONNECT_GRACE_MS) || 10000;
const BOT_MATCH_WAIT_MS = Number(process.env.BOT_MATCH_WAIT_MS) || 10000;
// Hitting this many mistakes ends the match — that player loses, the opponent
// wins. Stops players (or bots) from brute-forcing the board with guesses.
const MISTAKE_LIMIT = 4;

// Lightweight per-socket sliding-window rate limiter. Prevents a single
// connection from flooding join_queue / progress_update. State lives on the
// socket so it is GC'd on disconnect (no shared map to leak).
function rateLimit(socket, key, maxEvents, windowMs) {
  const now = Date.now();
  if (!socket.data.rate) socket.data.rate = {};
  const bucket = socket.data.rate[key] || [];
  const recent = bucket.filter((ts) => now - ts < windowMs);
  if (recent.length >= maxEvents) {
    socket.data.rate[key] = recent;
    return false;
  }
  recent.push(now);
  socket.data.rate[key] = recent;
  return true;
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

  botPlans.delete(gameId);
}

// How long a player of this rating would take to solve the board, in seconds.
// Piecewise-linear over realistic anchor points, then ±12% jitter, floored so
// even a top bot never finishes instantly. Bots are seeded 800–2000 (see
// seedBotUsers.gaussianRating); anchors extend a little past that for headroom.
const BOT_SOLVE_ANCHORS = [
  [800, 660], [1000, 510], [1200, 390], [1400, 300],
  [1600, 240], [1800, 190], [2000, 145], [2200, 120],
];
const BOT_SOLVE_FLOOR_S = 110;

function botSolveSeconds(rating) {
  const r = Number(rating) || 1200;
  const anchors = BOT_SOLVE_ANCHORS;
  let base;
  if (r <= anchors[0][0]) {
    base = anchors[0][1];
  } else if (r >= anchors[anchors.length - 1][0]) {
    base = anchors[anchors.length - 1][1];
  } else {
    base = anchors[anchors.length - 1][1];
    for (let i = 0; i < anchors.length - 1; i++) {
      const [r0, s0] = anchors[i];
      const [r1, s1] = anchors[i + 1];
      if (r >= r0 && r <= r1) {
        const t = (r - r0) / (r1 - r0);
        base = s0 + (s1 - s0) * t;
        break;
      }
    }
  }
  const jittered = base * (0.88 + Math.random() * 0.24);
  return Math.max(BOT_SOLVE_FLOOR_S, Math.round(jittered));
}

// A weaker bot is more mistake-prone. Roll a target 0–4; reaching MISTAKE_LIMIT
// (4) means the bot busts (forfeits) partway through, handing the human the win
// — the same elimination rule humans face.
function botMistakePlan(rating, solveMs) {
  const p = Math.max(0, Math.min(0.9, (1500 - (Number(rating) || 1200)) / 1400));
  let target = 0;
  for (let i = 0; i < MISTAKE_LIMIT; i++) {
    if (Math.random() < p) target++;
  }
  const willBust = target >= MISTAKE_LIMIT;
  // Bust somewhere in the first ~40–70% of the window, never right at the start.
  const bustAtMs = willBust
    ? Math.round(solveMs * (0.4 + Math.random() * 0.3))
    : null;
  return { mistakeTarget: target, bustAtMs };
}

function easeInOut(t) {
  return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
}

function emitBotProgress(io, gameId, botId) {
  const session = getSession(gameId);
  const plan = botPlans.get(gameId);
  if (!session || !session.progress?.[botId] || !plan) {
    clearBotSimulation(gameId);
    return;
  }

  const humanId = session.players.find((id) => id !== botId);
  if (!humanId) {
    clearBotSimulation(gameId);
    return;
  }

  const elapsed = Date.now() - plan.startedAt;

  // Mistake-bust path: the bot melts down mid-match and forfeits.
  if (plan.bustAtMs != null && elapsed >= plan.bustAtMs) {
    const bustResult = finishSession(gameId, humanId);
    clearBotSimulation(gameId);
    if (bustResult) {
      finalizeMatch(io, gameId, bustResult, 'bot_mistakes').catch((error) => {
        console.error('Failed to finalize bot-bust match:', error.message);
      });
    }
    return;
  }

  // Pace fill toward 100% along an ease-in-out curve so the meter moves
  // naturally and lands at ~full right when the bot finishes. Fill rises only —
  // no jitter — so the opponent meter never ticks backward.
  const frac = Math.max(0, Math.min(1, elapsed / plan.solveMs));
  const eased = easeInOut(frac);
  const targetFilled = Math.min(plan.emptyCells, Math.round(plan.emptyCells * eased));

  // Reveal mistakes gradually over the course of the solve.
  const mistakesShown = Math.min(
    plan.mistakeTarget,
    Math.floor(plan.mistakeTarget * frac + 0.0001),
  );

  const result = updateProgress(gameId, botId, {
    filledCells: targetFilled,
    mistakes: mistakesShown,
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

function startBotSimulation(io, gameId, botId, rating) {
  clearBotSimulation(gameId);

  const session = getSession(gameId);
  const emptyCells = session && Array.isArray(session.puzzle)
    ? session.puzzle.reduce(
        (sum, row) => sum + row.filter((value) => value === 0).length,
        0,
      )
    : 80;

  const solveMs = botSolveSeconds(rating) * 1000;
  const { mistakeTarget, bustAtMs } = botMistakePlan(rating, solveMs);

  botPlans.set(gameId, {
    startedAt: Date.now(),
    solveMs,
    emptyCells,
    mistakeTarget,
    bustAtMs,
  });

  const progressInterval = setInterval(() => {
    emitBotProgress(io, gameId, botId);
  }, 2500);

  botProgressIntervals.set(gameId, progressInterval);

  // Normal completion at the planned solve time (the bust path, if any, fires
  // earlier from emitBotProgress).
  const finishTimer = setTimeout(() => {
    const liveSession = getSession(gameId);
    if (!liveSession || !liveSession.progress?.[botId]) {
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
  }, solveMs);

  botFinishTimers.set(gameId, finishTimer);
}

// How far (in rating points) a bot opponent may sit from the human before
// it's no longer considered a "fair" pick. Unlike matchmakingService's
// wait-time bands (which widen the longer a *human* waits), the bot pool is
// static and never "waits", so a flat window is simpler and correct here.
const BOT_RATING_BAND = 150;

function pickBotFromPool(pool, targetRating) {
  if (!Array.isArray(pool) || pool.length === 0) return null;

  const ranked = pool
    .map((bot) => ({ bot, diff: Math.abs(bot.rating - targetRating) }))
    .sort((a, b) => a.diff - b.diff);

  const within = ranked.filter((entry) => entry.diff <= BOT_RATING_BAND);
  const candidates = within.length > 0 ? within : ranked.slice(0, 1);
  return candidates[Math.floor(Math.random() * candidates.length)].bot;
}

// Up to two attempts at fetching the live bot pool before giving up for this
// tick — a transient Supabase blip shouldn't be treated the same as the pool
// being genuinely unavailable.
async function pickBotForFallback(targetRating) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const pool = await getBotPool();
      const picked = pickBotFromPool(pool, targetRating);
      if (picked) return picked;
    } catch (error) {
      console.error(`Bot pool lookup failed (attempt ${attempt + 1}):`, error.message);
    }
  }
  return null;
}

function scheduleBotFallback(io, queuedPlayer) {
  clearQueueFallbackTimer(queuedPlayer.userId);

  const timer = setTimeout(async () => {
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

    // Claim the player and pull them off the queue synchronously (before the
    // bot-pool lookup below ever awaits) so a real opponent's findMatch can't
    // double-book them while we're mid-lookup.
    matchingUsers.add(liveQueuedPlayer.userId);
    removeFromQueue(liveQueuedPlayer.userId);

    try {
      const bot = await pickBotForFallback(liveQueuedPlayer.rating);
      if (!bot) {
        console.error(`No bot available for fallback match (player ${liveQueuedPlayer.userId})`);
        // Supabase is unreachable right now — put the player back in queue
        // and retry shortly rather than stranding them with no path to a
        // match.
        addToQueue(liveQueuedPlayer);
        scheduleBotFallback(io, liveQueuedPlayer);
        return;
      }

      const botId = bot.id;
      const playerId = liveQueuedPlayer.userId;

      const playersMeta = {
        [botId]: {
          userId: botId,
          username: bot.username,
          rating: bot.rating,
        },
        [playerId]: {
          userId: playerId,
          username: liveQueuedPlayer.username || playerId,
          rating: liveQueuedPlayer.rating,
        },
      };

      const { gameId, puzzle, solution } = createSession(botId, playerId, {
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
        solution,
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

      startBotSimulation(io, gameId, botId, bot.rating);
    } finally {
      matchingUsers.delete(liveQueuedPlayer.userId);
    }
  }, BOT_MATCH_WAIT_MS);

  queueFallbackTimers.set(queuedPlayer.userId, timer);
}

// Try to pair the given user with a compatible waiting opponent. Returns true
// if a match was created. Safe to call from both the join handler and the
// periodic sweep — the matchingUsers guard + immediate queue removal prevent
// double-booking. Looks the player up live each call so a stale snapshot can't
// pair someone who already left or matched.
async function attemptMatch(io, userId) {
  if (matchingUsers.has(userId)) return false;

  const self = getQueuedPlayer(userId);
  if (!self) return false;

  const selfSocket = io.sockets.sockets.get(self.socketId);
  if (!selfSocket) {
    removeFromQueue(self.userId);
    activeUsers.delete(self.userId);
    return false;
  }

  const opponent = findMatch(self);
  if (!opponent || opponent.userId === self.userId) return false;
  if (matchingUsers.has(opponent.userId)) return false;

  const opponentSocket = io.sockets.sockets.get(opponent.socketId);
  if (!opponentSocket) {
    removeFromQueue(opponent.userId);
    activeUsers.delete(opponent.userId);
    return false;
  }

  // Claim both and pull them off the queue synchronously, before any await, so
  // a concurrent sweep/join can't double-book either side.
  matchingUsers.add(self.userId);
  matchingUsers.add(opponent.userId);
  clearQueueFallbackTimer(self.userId);
  clearQueueFallbackTimer(opponent.userId);
  removeFromQueue(self.userId);
  removeFromQueue(opponent.userId);

  try {
    const player1Id = opponent.userId;
    const player2Id = self.userId;
    const playersMeta = {
      [player1Id]: {
        userId: player1Id,
        username: opponent.username || player1Id,
        rating: opponent.rating,
      },
      [player2Id]: {
        userId: player2Id,
        username: self.username || player2Id,
        rating: self.rating,
      },
    };

    const { gameId, puzzle, solution } = createSession(player1Id, player2Id, { playersMeta });

    opponentSocket.data.userId = player1Id;
    opponentSocket.data.gameId = gameId;
    selfSocket.data.userId = player2Id;
    selfSocket.data.gameId = gameId;

    setPlayerSocket(gameId, player1Id, opponentSocket.id);
    setPlayerSocket(gameId, player2Id, selfSocket.id);

    opponentSocket.join(gameId);
    selfSocket.join(gameId);

    io.to(gameId).emit('match_found', { gameId, puzzle, solution, playersMeta });

    const matchedAt = Date.now();
    const wait1 = Math.max(0, Math.floor((matchedAt - (opponent.joinedAt || matchedAt)) / 1000));
    const wait2 = Math.max(0, Math.floor((matchedAt - (self.joinedAt || matchedAt)) / 1000));
    Promise.all([
      logQueue({
        user_id: player1Id,
        joined_at: new Date(opponent.joinedAt || matchedAt).toISOString(),
        matched_at: new Date(matchedAt).toISOString(),
        wait_time: wait1,
      }),
      logQueue({
        user_id: player2Id,
        joined_at: new Date(self.joinedAt || matchedAt).toISOString(),
        matched_at: new Date(matchedAt).toISOString(),
        wait_time: wait2,
      }),
    ]).catch((error) => {
      console.error('Failed to write queue match log:', error.message);
    });

    return true;
  } finally {
    matchingUsers.delete(self.userId);
    matchingUsers.delete(opponent.userId);
  }
}

// Re-run matching across everyone still waiting. The join-time attempt only
// sees the rating band as it is at that instant; this sweep retries as each
// player's band widens with wait time, so two humans whose ratings differ
// always pair within a sweep interval instead of stranding on the bot fallback.
const MATCH_SWEEP_MS = 1500;
let matchSweepTimer = null;

function startMatchSweep(io) {
  if (matchSweepTimer) return;
  matchSweepTimer = setInterval(async () => {
    const waiting = getQueueSnapshot();
    for (const player of waiting) {
      if (matchingUsers.has(player.userId)) continue;
      // eslint-disable-next-line no-await-in-loop
      await attemptMatch(io, player.userId);
    }
  }, MATCH_SWEEP_MS);
  if (typeof matchSweepTimer.unref === 'function') matchSweepTimer.unref();
}

function isProgressValueInRange(value, min, max) {
  return Number.isInteger(value) && value >= min && value <= max;
}

// Pure, no DB: decide the rating change instantly from in-memory state. The ELO
// base is the rating captured in playersMeta at queue-join (fresh enough — every
// match requires a re-queue, which re-reads the DB rating). Works for human-vs-
// human and human-vs-bot alike (the bot's rating lives in playersMeta too).
function computeRatingUpdate(sessionResult) {
  if (!sessionResult || !Array.isArray(sessionResult.players) || sessionResult.players.length !== 2) {
    return null;
  }

  const [player1Id, player2Id] = sessionResult.players;
  const meta = sessionResult.playersMeta || {};
  const oldRating1 = Number(meta[player1Id]?.rating ?? 1200);
  const oldRating2 = Number(meta[player2Id]?.rating ?? 1200);
  const winnerId = sessionResult.winnerId;

  const player1Score = winnerId === player1Id ? 1 : 0;
  const player2Score = winnerId === player2Id ? 1 : 0;

  const newRating1 = calculateElo(oldRating1, oldRating2, player1Score);
  const newRating2 = calculateElo(oldRating2, oldRating1, player2Score);

  return {
    player1Id,
    player2Id,
    winnerId,
    loserId: sessionResult.loserId,
    ratings: { [player1Id]: newRating1, [player2Id]: newRating2 },
    deltas: {
      [player1Id]: newRating1 - oldRating1,
      [player2Id]: newRating2 - oldRating2,
    },
    previousRatings: { [player1Id]: oldRating1, [player2Id]: oldRating2 },
  };
}

// Writes a finished match to the DB. Bot opponents are real `users` rows now,
// so a bot match is written exactly like a human-vs-human one — same `games`
// row, same two-sided stat increments.
async function persistMatchResult(sessionResult, ratingUpdate = null) {
  if (!sessionResult || !Array.isArray(sessionResult.players) || sessionResult.players.length !== 2) {
    return null;
  }

  const [player1Id, player2Id] = sessionResult.players;
  const winnerId = sessionResult.winnerId;

  const winnerMistakes = sessionResult.progress?.[winnerId]?.mistakes || 0;

  let ratingDelta = 0;
  if (ratingUpdate && ratingUpdate.deltas && winnerId) {
    ratingDelta = ratingUpdate.deltas[winnerId] || 0;
  }

  return storeMatchResult({
    seed: sessionResult.seed,
    player1_id: player1Id,
    player2_id: player2Id,
    winner_id: winnerId,
    duration: sessionResult.duration || 0,
    mistakes: winnerMistakes,
    rating_delta: ratingDelta,
  });
}

// All DB work, off the player's critical path. Errors are logged, never thrown.
async function persistMatchAsync(sessionResult, ratingUpdate, reason, gameId) {
  if (!sessionResult || !Array.isArray(sessionResult.players)) return;

  const [player1Id, player2Id] = sessionResult.players;
  const isBotMatch = sessionResult.isBotMatch === true;

  // 1. Persist new ratings. Additive (delta) RPC, not a plain SET — a bot
  // row can be in several concurrent matches at once, so this must be atomic
  // for bots; it's an equally-safe no-op-equivalent for humans.
  if (ratingUpdate) {
    const writes = [];
    for (const pid of sessionResult.players) {
      const delta = ratingUpdate.deltas[pid];
      if (typeof delta === 'number') writes.push(incrementUserRating(pid, delta));
    }
    try {
      await Promise.all(writes);
    } catch (error) {
      console.error('Failed to persist ratings:', error.message);
    }
  }

  // 2. Match record + win/loss stats.
  try {
    await persistMatchResult(sessionResult, ratingUpdate);
  } catch (error) {
    console.error('Failed to persist match result:', error.message);
  }

  // 3. Analytics logs — bot matches are synthetic, keep them out of
  // match-quality/anti-cheat analytics entirely (intentional, not a type
  // constraint — bot ids are real uuids now too).
  if (!isBotMatch) {
    try {
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
          details: { duration: sessionResult.duration || 0 },
        });
      } catch (error) {
        console.error('Failed to write suspicious solve log:', error.message);
      }
    }
  }
}

async function finalizeMatch(io, gameId, sessionResult, reason) {
  clearBotSimulation(gameId);

  for (const playerId of sessionResult.players || []) {
    const timer = disconnectTimers.get(playerId);
    if (timer) {
      clearTimeout(timer);
      disconnectTimers.delete(playerId);
    }
  }

  // Decide + broadcast instantly: the board was already validated server-side,
  // so the winner is known. No DB on the critical path → result + ELO land in
  // one round trip (<200ms), never blocked by Supabase latency.
  const ratingUpdate = computeRatingUpdate(sessionResult);

  io.to(gameId).emit('game_end', {
    gameId,
    ...sessionResult,
    reason,
    persistedMatch: null,
    ratingUpdate,
  });

  if (ratingUpdate) {
    io.to(gameId).emit('rating_update', ratingUpdate);
  }

  await cleanupRoom(io, gameId);

  // Persist in the background — players already have their result.
  void persistMatchAsync(sessionResult, ratingUpdate, reason, gameId);
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
  // Verifies the Supabase JWT on the handshake when SUPABASE_JWT_SECRET is set;
  // no-op otherwise (keeps local testing working without a secret).
  io.use(socketAuth);

  // Background re-matcher: pairs waiting humans as their rating bands widen.
  startMatchSweep(io);

  io.on('connection', (socket) => {
    socket.on('join_queue', async (payload = {}) => {
      // Max 5 queue attempts / 10s per socket.
      if (!rateLimit(socket, 'join_queue', 5, 10000)) return;
      // When auth is on, trust the verified token id, never the payload.
      const userId = socket.data.authUserId
        || (typeof payload.userId === 'string' ? payload.userId : null);
      if (!userId) return;

      if (activeUsers.has(userId)) {
        return;
      }

      // Re-queuing always starts a fresh match — never force a resume. If a
      // stale session lingers (app killed mid-game, etc.), abandon it: forfeit
      // it to the opponent so they aren't stranded, then fall through and queue.
      const activeGameId = getUserSession(userId);
      if (activeGameId && getSession(activeGameId)) {
        const stale = getSession(activeGameId);
        const opponentId = stale.players.find((id) => id !== userId) || userId;
        const finished = finishSession(activeGameId, opponentId);
        if (finished) {
          finalizeMatch(io, activeGameId, finished, 'opponent_left').catch((error) => {
            console.error('Failed to finalize abandoned match:', error.message);
          });
        }
      }

      let rating = 1200;
      let username = userId;
      try {
        // Always fetch the latest rating from DB at queue-join time. Bounded
        // so a slow/cold Supabase call can never stall matchmaking itself —
        // a timeout just means this one queue-join uses the default rating.
        const user = await withTimeout(getUserById(userId), 2500, null);
        if (user === null) {
          console.error(`getUserById timed out or failed for ${userId}, queueing at default rating`);
        }
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

      // Instant pair if a compatible opponent is already waiting; otherwise the
      // periodic sweep (started in initializeSocketServer) keeps retrying as the
      // rating band widens, and the bot fallback fires if no human shows up.
      const matched = await attemptMatch(io, queuedPlayer.userId);
      if (!matched) {
        scheduleBotFallback(io, queuedPlayer);
      }
    });

    socket.on('progress_update', async (payload = {}) => {
      const gameId = payload.gameId || socket.data.gameId;
      const playerId = socket.data.authUserId
        || payload.userId
        || socket.data.userId;

      if (!gameId || !playerId) return;

      // Throttle progress spam to 25/s, but never drop a completion claim
      // (that path is server-validated against the solution anyway).
      if (payload.completed !== true && !rateLimit(socket, 'progress', 25, 1000)) {
        return;
      }

      const data = {};

      if (payload.filledCells !== undefined) {
        if (!isProgressValueInRange(payload.filledCells, 0, 81)) return;
        data.filledCells = payload.filledCells;
      }

      if (payload.mistakes !== undefined) {
        if (!isProgressValueInRange(payload.mistakes, 0, MISTAKE_LIMIT)) return;
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

      // Elimination: the 4th mistake ends the match — this player loses, the
      // opponent wins. Server-authoritative so both clients resolve together.
      const liveSession = getSession(gameId);
      if (liveSession && (liveSession.progress?.[playerId]?.mistakes || 0) >= MISTAKE_LIMIT) {
        const opponentId = liveSession.players.find((id) => id !== playerId);
        if (opponentId) {
          const finished = finishSession(gameId, opponentId);
          if (finished) {
            await finalizeMatch(io, gameId, finished, 'too_many_mistakes');
            return;
          }
        }
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

    // Explicit "I surrender" — finalize immediately instead of waiting out the
    // DISCONNECT_GRACE_MS reconnect window, since intent here is unambiguous
    // (unlike a plain disconnect, which could be an accidental drop).
    socket.on('surrender', ({ gameId } = {}) => {
      const userId = socket.data.userId;
      const resolvedGameId = gameId || socket.data.gameId;
      if (!userId || !resolvedGameId) return;

      const liveSession = getSession(resolvedGameId);
      if (!liveSession) return;

      const opponentId = liveSession.players.find((id) => id !== userId);
      if (!opponentId) return;

      const previousTimer = disconnectTimers.get(userId);
      if (previousTimer) {
        clearTimeout(previousTimer);
        disconnectTimers.delete(userId);
      }

      const finishedResult = finishSession(resolvedGameId, opponentId);
      if (!finishedResult) return;

      finalizeMatch(io, resolvedGameId, finishedResult, 'surrendered').catch((error) => {
        console.error('Failed to finalize surrendered match:', error.message);
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
