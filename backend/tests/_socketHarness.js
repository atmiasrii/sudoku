const path = require('path');
const http = require('http');
const express = require('express');
const { Server } = require('socket.io');
const { io: ioClient } = require('socket.io-client');

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function createInMemoryDb(seedUsers) {
  const users = new Map();
  const games = [];
  const logs = {
    match_logs: [],
    suspicious_activity: [],
    disconnect_logs: [],
    error_logs: [],
    queue_logs: [],
  };

  for (const user of seedUsers) {
    users.set(user.id, {
      id: user.id,
      username: user.username || user.id,
      rating: Number(user.rating ?? 1200),
      games_played: Number(user.games_played ?? 0),
      wins: Number(user.wins ?? 0),
      losses: Number(user.losses ?? 0),
      is_bot: user.is_bot === true,
    });
  }

  const userService = {
    async getUserById(userId) {
      const user = users.get(userId);
      return user ? clone(user) : null;
    },
    async updateUserRating(userId, newRating) {
      const existing = users.get(userId) || {
        id: userId,
        username: userId,
        rating: 1200,
        games_played: 0,
        wins: 0,
        losses: 0,
        is_bot: false,
      };

      const next = {
        ...existing,
        rating: Number(newRating),
      };

      users.set(userId, next);
      return clone(next);
    },
    async incrementUserRating(userId, delta) {
      const existing = users.get(userId) || {
        id: userId,
        username: userId,
        rating: 1200,
        games_played: 0,
        wins: 0,
        losses: 0,
        is_bot: false,
      };

      const next = {
        ...existing,
        rating: Number(existing.rating) + Number(delta),
      };

      users.set(userId, next);
      return clone(next);
    },
    async getBotPool() {
      return [...users.values()]
        .filter((user) => user.is_bot === true)
        .map(clone);
    },
    async getLeaderboard(limit = 10) {
      return [...users.values()]
        .sort((a, b) => b.rating - a.rating)
        .slice(0, limit)
        .map(clone);
    },
  };

  const gameService = {
    async storeMatchResult(matchData) {
      const record = {
        id: `game_${games.length + 1}`,
        ...clone(matchData),
      };
      games.push(record);

      const p1 = users.get(matchData.player1_id);
      const p2 = users.get(matchData.player2_id);
      if (p1) p1.games_played += 1;
      if (p2) p2.games_played += 1;

      if (matchData.winner_id === matchData.player1_id) {
        if (p1) p1.wins += 1;
        if (p2) p2.losses += 1;
      } else if (matchData.winner_id === matchData.player2_id) {
        if (p2) p2.wins += 1;
        if (p1) p1.losses += 1;
      }

      return clone(record);
    },
  };

  const logService = {
    async logMatch(data) {
      logs.match_logs.push(clone(data));
      return { ok: true };
    },
    async logSuspicious(data) {
      logs.suspicious_activity.push(clone(data));
      return { ok: true };
    },
    async logDisconnect(data) {
      logs.disconnect_logs.push(clone(data));
      return { ok: true };
    },
    async logError(data) {
      logs.error_logs.push(clone(data));
      return { ok: true };
    },
    async logQueue(data) {
      logs.queue_logs.push(clone(data));
      return { ok: true };
    },
    getLoggingStatus() {
      return { enabled: true, reason: null };
    },
  };

  return { users, games, logs, userService, gameService, logService };
}

function makeCacheEntry(filePath, exportsValue) {
  return {
    id: filePath,
    filename: filePath,
    loaded: true,
    exports: exportsValue,
  };
}

async function createSocketTestEnvironment(options = {}) {
  const backendRoot = path.resolve(__dirname, '..');
  const socketServerPath = path.join(backendRoot, 'websocket', 'socketServer.js');
  const userServicePath = path.join(backendRoot, 'services', 'userService.js');
  const gameServicePath = path.join(backendRoot, 'services', 'gameService.js');
  const sessionServicePath = path.join(backendRoot, 'services', 'gameSessionService.js');
  const logServicePath = path.join(backendRoot, 'services', 'logService.js');

  const db = createInMemoryDb(options.users || []);

  const previousUserService = require.cache[userServicePath];
  const previousGameService = require.cache[gameServicePath];
  const previousSocketServer = require.cache[socketServerPath];
  const previousLogService = require.cache[logServicePath];

  require.cache[userServicePath] = makeCacheEntry(userServicePath, db.userService);
  require.cache[gameServicePath] = makeCacheEntry(gameServicePath, db.gameService);
  require.cache[logServicePath] = makeCacheEntry(logServicePath, db.logService);
  delete require.cache[socketServerPath];

  const sessionService = require(sessionServicePath);
  sessionService.sessions.clear();
  sessionService.userSessions.clear();

  const { initializeSocketServer } = require(socketServerPath);

  const app = express();
  const server = http.createServer(app);
  const io = new Server(server, {
    cors: { origin: '*' },
  });

  initializeSocketServer(io);

  const sockets = [];

  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const url = `http://127.0.0.1:${address.port}`;

  function connectClient() {
    const socket = ioClient(url, {
      transports: ['websocket'],
      forceNew: true,
      reconnection: false,
    });
    sockets.push(socket);
    return socket;
  }

  function waitForEvent(socket, eventName, timeoutMs = 3000, predicate = null) {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        socket.off(eventName, onEvent);
        reject(new Error(`Timed out waiting for ${eventName}`));
      }, timeoutMs);

      function onEvent(payload) {
        if (predicate && !predicate(payload)) {
          return;
        }
        clearTimeout(timeout);
        socket.off(eventName, onEvent);
        resolve(payload);
      }

      socket.on(eventName, onEvent);
    });
  }

  async function close() {
    for (const socket of sockets) {
      try {
        socket.removeAllListeners();
        socket.disconnect();
      } catch (_) {
        // no-op
      }
    }

    await new Promise((resolve) => io.close(resolve));
    await new Promise((resolve) => server.close(resolve));

    sessionService.sessions.clear();
    sessionService.userSessions.clear();

    delete require.cache[socketServerPath];

    if (previousUserService) {
      require.cache[userServicePath] = previousUserService;
    } else {
      delete require.cache[userServicePath];
    }

    if (previousGameService) {
      require.cache[gameServicePath] = previousGameService;
    } else {
      delete require.cache[gameServicePath];
    }

    if (previousSocketServer) {
      require.cache[socketServerPath] = previousSocketServer;
    }

    if (previousLogService) {
      require.cache[logServicePath] = previousLogService;
    } else {
      delete require.cache[logServicePath];
    }
  }

  return {
    url,
    io,
    db,
    connectClient,
    waitForEvent,
    close,
    sessionService,
  };
}

module.exports = {
  createSocketTestEnvironment,
};
