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
  await runSuite('Anti-Cheat', [
    {
      name: 'invalid completion payloads are rejected and session remains active',
      run: async () => {
        const env = await createSocketTestEnvironment({
          users: [
            { id: 'ac1', rating: 1300 },
            { id: 'ac2', rating: 1300 },
          ],
        });

        try {
          const c1 = env.connectClient();
          const c2 = env.connectClient();
          await Promise.all([waitForConnect(c1), waitForConnect(c2)]);

          const m1 = env.waitForEvent(c1, 'match_found');
          env.waitForEvent(c2, 'match_found');
          c1.emit('join_queue', { userId: 'ac1' });
          c2.emit('join_queue', { userId: 'ac2' });
          const match = await m1;
          const gameId = match.gameId;

          const rejected1 = env.waitForEvent(c1, 'progress_rejected');
          c1.emit('progress_update', { gameId, userId: 'ac1', completed: true });
          const missingBoard = await rejected1;
          assert.ok(/Invalid board payload/.test(missingBoard.message));
          assert.ok(env.sessionService.getSession(gameId));

          const rejected2 = env.waitForEvent(c1, 'progress_rejected');
          c1.emit('progress_update', { gameId, userId: 'ac1', completed: true, board: [[1, 2, 3]] });
          const malformed = await rejected2;
          assert.ok(/Invalid board payload/.test(malformed.message));
          assert.ok(env.sessionService.getSession(gameId));

          const session = env.sessionService.getSession(gameId);
          const partialWrong = deepClone(session.solution);
          partialWrong[0][0] = partialWrong[0][0] % 9 + 1;

          const rejected3 = env.waitForEvent(c1, 'progress_rejected');
          c1.emit('progress_update', { gameId, userId: 'ac1', completed: true, board: partialWrong });
          const wrongBoard = await rejected3;
          assert.ok(/Invalid solution/.test(wrongBoard.message));
          assert.ok(env.sessionService.getSession(gameId));

          const invalidBoardLogs = env.db.logs.suspicious_activity.filter((l) => l.reason === 'invalid_board');
          assert.ok(invalidBoardLogs.length >= 3);
        } finally {
          await env.close();
        }
      },
    },
    {
      name: 'valid solution accepted and duplicate completion attempts do not re-finish',
      run: async () => {
        const env = await createSocketTestEnvironment({
          users: [
            { id: 'ac3', rating: 1200 },
            { id: 'ac4', rating: 1200 },
          ],
        });

        try {
          const c1 = env.connectClient();
          const c2 = env.connectClient();
          await Promise.all([waitForConnect(c1), waitForConnect(c2)]);

          const matchPromise = env.waitForEvent(c1, 'match_found');
          env.waitForEvent(c2, 'match_found');
          c1.emit('join_queue', { userId: 'ac3' });
          c2.emit('join_queue', { userId: 'ac4' });

          const match = await matchPromise;
          const gameId = match.gameId;
          const session = env.sessionService.getSession(gameId);

          const gameEnd = env.waitForEvent(c1, 'game_end');
          c1.emit('progress_update', {
            gameId,
            userId: 'ac3',
            completed: true,
            board: deepClone(session.solution),
          });

          const result = await gameEnd;
          assert.strictEqual(result.winnerId, 'ac3');
          assert.strictEqual(env.sessionService.getSession(gameId), undefined);

          // Attempt duplicate completion after finish should produce no new game_end.
          let duplicateTriggered = false;
          c1.once('game_end', () => {
            duplicateTriggered = true;
          });
          c1.emit('progress_update', {
            gameId,
            userId: 'ac3',
            completed: true,
            board: deepClone(session.solution),
          });

          await new Promise((resolve) => setTimeout(resolve, 300));
          assert.strictEqual(duplicateTriggered, false);
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
