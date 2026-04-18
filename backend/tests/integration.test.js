const { assert, runSuite, deepClone } = require('./_runner');
const { createSocketTestEnvironment } = require('./_socketHarness');

function waitForConnect(socket, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('connect timeout')), timeoutMs);
    socket.on('connect', () => {
      clearTimeout(timeout);
      resolve();
    });
  });
}

async function run() {
  await runSuite('Full Integration', [
    {
      name: 'complete multiplayer flow with DB persistence and leaderboard consistency',
      run: async () => {
        const env = await createSocketTestEnvironment({
          users: [
            { id: 'in1', rating: 1200 },
            { id: 'in2', rating: 1220 },
            { id: 'in3', rating: 1190 },
          ],
        });

        try {
          const c1 = env.connectClient();
          const c2 = env.connectClient();
          await Promise.all([waitForConnect(c1), waitForConnect(c2)]);

          const m1 = env.waitForEvent(c1, 'match_found');
          const m2 = env.waitForEvent(c2, 'match_found');

          c1.emit('join_queue', { userId: 'in1' });
          c2.emit('join_queue', { userId: 'in2' });

          const match1 = await m1;
          const match2 = await m2;
          const gameId = match1.gameId;

          assert.strictEqual(match1.gameId, match2.gameId);
          assert.deepStrictEqual(match1.puzzle, match2.puzzle);

          const seen = [];
          c1.on('progress_update', () => seen.push('progress_update'));
          c1.on('game_end', () => seen.push('game_end'));
          c1.on('rating_update', () => seen.push('rating_update'));

          const s = env.sessionService.getSession(gameId);
          assert.ok(s);

          c1.emit('progress_update', {
            gameId,
            userId: 'in1',
            filledCells: 10,
            mistakes: 0,
            completed: false,
          });

          const gameEndPromise = env.waitForEvent(c1, 'game_end');
          const ratingPromise = env.waitForEvent(c1, 'rating_update');

          c1.emit('progress_update', {
            gameId,
            userId: 'in1',
            filledCells: 50,
            mistakes: 1,
            completed: true,
            board: deepClone(s.solution),
          });

          const gameEnd = await gameEndPromise;
          const rating = await ratingPromise;

          assert.strictEqual(gameEnd.reason, 'completed');
          assert.strictEqual(gameEnd.winnerId, 'in1');
          assert.strictEqual(gameEnd.loserId, 'in2');
          assert.ok(gameEnd.persistedMatch);
          assert.ok(gameEnd.ratingUpdate);

          assert.ok(rating.ratings.in1 > 1200);
          assert.ok(rating.ratings.in2 < 1220);

          assert.strictEqual(env.db.games.length, 1);
          assert.strictEqual(env.db.games[0].winner_id, 'in1');

          assert.strictEqual(env.db.logs.match_logs.length, 1);
          assert.strictEqual(env.db.logs.match_logs[0].reason, 'completed');
          assert.strictEqual(env.db.logs.match_logs[0].winner_id, 'in1');
          assert.strictEqual(env.db.logs.match_logs[0].loser_id, 'in2');

          const leaderboard = await env.db.userService.getLeaderboard(3);
          const in1 = leaderboard.find((u) => u.id === 'in1');
          const in2 = leaderboard.find((u) => u.id === 'in2');
          assert.ok(in1.rating > 1200);
          assert.ok(in2.rating < 1220);

          assert.strictEqual(env.sessionService.getSession(gameId), undefined);

          const gameEndCount = seen.filter((e) => e === 'game_end').length;
          const ratingCount = seen.filter((e) => e === 'rating_update').length;
          assert.strictEqual(gameEndCount, 1);
          assert.strictEqual(ratingCount, 1);
          assert.ok(seen.indexOf('game_end') < seen.indexOf('rating_update'));
        } finally {
          await env.close();
        }
      },
    },
    {
      name: 'bonus: rapid progress spam and 10 concurrent matches do not leak sessions',
      run: async () => {
        const users = [];
        for (let i = 0; i < 20; i += 1) {
          users.push({ id: `bulk_${i}`, rating: 1200 + (i % 5) * 10 });
        }

        const env = await createSocketTestEnvironment({ users });

        try {
          const clients = users.map(() => env.connectClient());
          await Promise.all(clients.map((c) => waitForConnect(c)));

          const matchEvents = clients.map((c) => env.waitForEvent(c, 'match_found', 5000));
          users.forEach((u, idx) => {
            clients[idx].emit('join_queue', { userId: u.id });
          });

          await Promise.all(matchEvents);

          const activeSessionCount = env.sessionService.sessions.size;
          assert.strictEqual(activeSessionCount, 10);

          const [firstClient] = clients;
          const firstSession = [...env.sessionService.sessions.entries()][0];
          const [gameId, session] = firstSession;
          const playerId = session.players[0];

          for (let i = 0; i < 30; i += 1) {
            firstClient.emit('progress_update', {
              gameId,
              userId: playerId,
              filledCells: Math.min(i, 81),
              mistakes: i % 3,
              completed: false,
            });
          }

          // End all sessions cleanly.
          const endPromises = [];
          for (const [gId, live] of env.sessionService.sessions) {
            const winner = live.players[0];
            const client = clients.find((c) => c.connected && c.id === live.playerSockets[winner]) || clients[0];
            endPromises.push(env.waitForEvent(client, 'game_end', 5000));
            client.emit('progress_update', {
              gameId: gId,
              userId: winner,
              completed: true,
              board: deepClone(live.solution),
            });
          }

          await Promise.all(endPromises);
          assert.strictEqual(env.sessionService.sessions.size, 0);
          assert.ok(env.db.logs.match_logs.length >= 10);
        } finally {
          await env.close();
        }
      },
    },
  ]);
}

if (require.main === module) {
  run().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = { run };
