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
  await runSuite('WebSocket Multiplayer', [
    {
      name: 'two clients connect, match, sync progress, and finish',
      run: async () => {
        const env = await createSocketTestEnvironment({
          users: [
            { id: 'ws1', rating: 1200 },
            { id: 'ws2', rating: 1210 },
          ],
        });

        try {
          const c1 = env.connectClient();
          const c2 = env.connectClient();
          await Promise.all([waitForConnect(c1), waitForConnect(c2)]);

          const c1Match = env.waitForEvent(c1, 'match_found');
          const c2Match = env.waitForEvent(c2, 'match_found');

          c1.emit('join_queue', { userId: 'ws1' });
          c2.emit('join_queue', { userId: 'ws2' });

          const m1 = await c1Match;
          const m2 = await c2Match;

          assert.strictEqual(m1.gameId, m2.gameId);
          assert.deepStrictEqual(m1.puzzle, m2.puzzle);

          const gameId = m1.gameId;
          const liveSession = env.sessionService.getSession(gameId);
          assert.ok(liveSession);

          const c2Progress = env.waitForEvent(c2, 'progress_update', 3000, (p) => p.playerId === 'ws1' && p.finished === false);
          c1.emit('progress_update', {
            gameId,
            userId: 'ws1',
            filledCells: 12,
            mistakes: 1,
            completed: false,
          });
          const progressPayload = await c2Progress;
          assert.strictEqual(progressPayload.session.progress.ws1.filledCells, 12);

          const c1GameEnd = env.waitForEvent(c1, 'game_end');
          const c1Rating = env.waitForEvent(c1, 'rating_update');

          c1.emit('progress_update', {
            gameId,
            userId: 'ws1',
            filledCells: 40,
            mistakes: 1,
            completed: true,
            board: deepClone(liveSession.solution),
          });

          const gameEndPayload = await c1GameEnd;
          const ratingPayload = await c1Rating;

          assert.strictEqual(gameEndPayload.reason, 'completed');
          assert.strictEqual(gameEndPayload.winnerId, 'ws1');
          assert.strictEqual(gameEndPayload.loserId, 'ws2');
          assert.ok(ratingPayload.ratings.ws1 > 1200);
          assert.strictEqual(env.sessionService.getSession(gameId), undefined);
        } finally {
          await env.close();
        }
      },
    },
    {
      name: 'single queued player is matched with bot after timeout',
      run: async () => {
        const env = await createSocketTestEnvironment({
          users: [
            { id: 'solo1', rating: 1330 },
            { id: 'bot-fixture-1', username: 'TestBot', rating: 1300, is_bot: true },
          ],
        });

        try {
          const c1 = env.connectClient();
          await waitForConnect(c1);

          const matchFound = env.waitForEvent(c1, 'match_found', 7000);
          c1.emit('join_queue', { userId: 'solo1' });

          const payload = await matchFound;
          assert.ok(payload.gameId);
          assert.ok(payload.playersMeta);

          const playerIds = Object.keys(payload.playersMeta);
          assert.strictEqual(playerIds.length, 2);
          assert.ok(playerIds.includes('solo1'));

          const botId = playerIds.find((id) => id !== 'solo1');
          assert.strictEqual(botId, 'bot-fixture-1');

          const liveSession = env.sessionService.getSession(payload.gameId);
          assert.ok(liveSession);
          assert.strictEqual(liveSession.isBotMatch, true);
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
