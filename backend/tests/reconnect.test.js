const { assert, runSuite, delay } = require('./_runner');
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
  process.env.DISCONNECT_GRACE_MS = '400';

  await runSuite('Reconnect System', [
    {
      name: 'reconnect within grace restores game_state and cancels timeout loss',
      run: async () => {
        const env = await createSocketTestEnvironment({
          users: [
            { id: 'rc1', rating: 1200 },
            { id: 'rc2', rating: 1200 },
          ],
        });

        try {
          const c1 = env.connectClient();
          const c2 = env.connectClient();
          await Promise.all([waitForConnect(c1), waitForConnect(c2)]);

          const m1 = env.waitForEvent(c1, 'match_found');
          const m2 = env.waitForEvent(c2, 'match_found');
          c1.emit('join_queue', { userId: 'rc1' });
          c2.emit('join_queue', { userId: 'rc2' });
          const match = await m1;
          await m2;

          const gameId = match.gameId;
          const opponentDisconnected = env.waitForEvent(c2, 'opponent_disconnected');
          c1.disconnect();
          await opponentDisconnected;

          const c1Reconnect = env.connectClient();
          await waitForConnect(c1Reconnect);

          const gameStatePromise = env.waitForEvent(c1Reconnect, 'game_state');
          const opponentReconnected = env.waitForEvent(c2, 'opponent_reconnected');
          c1Reconnect.emit('reconnect_game', { userId: 'rc1', gameId });

          const state = await gameStatePromise;
          await opponentReconnected;

          assert.strictEqual(state.gameId, gameId);
          assert.ok(state.progress.rc1);
          assert.ok(env.sessionService.getSession(gameId));

          await delay(500);
          assert.ok(env.sessionService.getSession(gameId));

          const reconnectLogs = env.db.logs.disconnect_logs.filter((l) => l.type === 'reconnect' && l.user_id === 'rc1');
          assert.ok(reconnectLogs.length >= 1);
        } finally {
          await env.close();
        }
      },
    },
    {
      name: 'no reconnect leads to opponent_disconnected win after timeout',
      run: async () => {
        const env = await createSocketTestEnvironment({
          users: [
            { id: 'rc3', rating: 1200 },
            { id: 'rc4', rating: 1200 },
          ],
        });

        try {
          const c1 = env.connectClient();
          const c2 = env.connectClient();
          await Promise.all([waitForConnect(c1), waitForConnect(c2)]);

          const m1 = env.waitForEvent(c1, 'match_found');
          const m2 = env.waitForEvent(c2, 'match_found');
          c1.emit('join_queue', { userId: 'rc3' });
          c2.emit('join_queue', { userId: 'rc4' });
          const match = await m1;
          await m2;

          const gameEnd = env.waitForEvent(c2, 'game_end');
          c1.disconnect();

          const endPayload = await gameEnd;
          assert.strictEqual(endPayload.reason, 'opponent_disconnected');
          assert.strictEqual(endPayload.winnerId, 'rc4');
          assert.strictEqual(env.sessionService.getSession(match.gameId), undefined);

          const disconnectLogs = env.db.logs.disconnect_logs.filter((l) => l.type === 'disconnect' && l.user_id === 'rc3');
          assert.ok(disconnectLogs.length >= 1);
        } finally {
          await env.close();
        }
      },
    },
  ]);

  delete process.env.DISCONNECT_GRACE_MS;
}

if (require.main === module) {
  run().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = { run };
