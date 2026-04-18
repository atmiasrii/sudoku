const { assert, runSuite } = require('./_runner');
const {
  sessions,
  userSessions,
  createSession,
  getSession,
  updateProgress,
  finishSession,
} = require('../services/gameSessionService');

function resetSessionState() {
  sessions.clear();
  userSessions.clear();
}

async function run() {
  resetSessionState();

  await runSuite('Session Manager', [
    {
      name: 'createSession creates valid session and registers players',
      run: async () => {
        const created = createSession('u1', 'u2');
        const session = getSession(created.gameId);

        assert.ok(session);
        assert.strictEqual(session.status, 'active');
        assert.deepStrictEqual(session.players, ['u1', 'u2']);
        assert.ok(Array.isArray(session.puzzle));
        assert.ok(Array.isArray(session.solution));
        assert.strictEqual(userSessions.get('u1'), created.gameId);
        assert.strictEqual(userSessions.get('u2'), created.gameId);
      },
    },
    {
      name: 'progress updates modify session state',
      run: async () => {
        const created = createSession('p1', 'p2');
        const updated = updateProgress(created.gameId, 'p1', { filledCells: 12, mistakes: 1 });

        assert.ok(updated);
        assert.strictEqual(updated.progress.p1.filledCells, 12);
        assert.strictEqual(updated.progress.p1.mistakes, 1);
      },
    },
    {
      name: 'auto-win triggers on valid completed=true and deletes session',
      run: async () => {
        const created = createSession('w1', 'w2');
        const session = getSession(created.gameId);
        const result = updateProgress(created.gameId, 'w1', {
          completed: true,
          board: session.solution,
        });

        assert.ok(result);
        assert.strictEqual(result.status, 'finished');
        assert.strictEqual(result.winnerId, 'w1');
        assert.strictEqual(result.loserId, 'w2');
        assert.strictEqual(getSession(created.gameId), undefined);
      },
    },
    {
      name: 'invalid progress values are rejected',
      run: async () => {
        const created = createSession('v1', 'v2');

        const badFilled = updateProgress(created.gameId, 'v1', { filledCells: -1 });
        const tooManyFilled = updateProgress(created.gameId, 'v1', { filledCells: 82 });
        const badMistakes = updateProgress(created.gameId, 'v1', { mistakes: 4 });

        assert.strictEqual(badFilled.error, 'Invalid filledCells');
        assert.strictEqual(tooManyFilled.error, 'Invalid filledCells');
        assert.strictEqual(badMistakes.error, 'Invalid mistakes');
      },
    },
    {
      name: 'non-existent and already-finished sessions are handled',
      run: async () => {
        const missingUpdate = updateProgress('missing', 'nobody', { filledCells: 1 });
        assert.strictEqual(missingUpdate, null);

        const created = createSession('f1', 'f2');
        const finished = finishSession(created.gameId, 'f1');
        assert.ok(finished);

        const secondFinish = finishSession(created.gameId, 'f1');
        assert.strictEqual(secondFinish, null);
      },
    },
  ]);

  resetSessionState();
}

if (require.main === module) {
  run().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = { run };
