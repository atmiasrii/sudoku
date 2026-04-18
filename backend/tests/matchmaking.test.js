const { assert, runSuite } = require('./_runner');
const {
  addToQueue,
  findMatch,
  removeFromQueue,
} = require('../services/matchmakingService');

function clean(ids) {
  for (const id of ids) {
    removeFromQueue(id);
  }
}

function ago(seconds) {
  return Date.now() - seconds * 1000;
}

async function run() {
  const ids = ['a', 'b', 'c', 'd', 'e', 'self', 'race1', 'race2'];
  clean(ids);

  await runSuite('Matchmaking', [
    {
      name: 'players in rating range are matched',
      run: async () => {
        const a = addToQueue({ userId: 'a', rating: 1200, socketId: 's-a' });
        addToQueue({ userId: 'b', rating: 1260, socketId: 's-b' });

        const match = findMatch(a);
        assert.ok(match);
        assert.strictEqual(match.userId, 'b');
        clean(['a', 'b']);
      },
    },
    {
      name: 'players outside range are not matched initially',
      run: async () => {
        const a = addToQueue({ userId: 'a', rating: 1200, socketId: 's-a', joinedAt: ago(1) });
        addToQueue({ userId: 'c', rating: 1600, socketId: 's-c', joinedAt: ago(1) });

        const match = findMatch(a);
        assert.strictEqual(match, null);
        clean(['a', 'c']);
      },
    },
    {
      name: 'rating range expands over time',
      run: async () => {
        const a = addToQueue({ userId: 'a', rating: 1200, socketId: 's-a', joinedAt: ago(16) });
        addToQueue({ userId: 'd', rating: 1580, socketId: 's-d', joinedAt: ago(16) });

        const match = findMatch(a);
        assert.ok(match);
        assert.strictEqual(match.userId, 'd');
        clean(['a', 'd']);
      },
    },
    {
      name: 'closest rating match selected',
      run: async () => {
        const a = addToQueue({ userId: 'a', rating: 1200, socketId: 's-a' });
        addToQueue({ userId: 'b', rating: 1230, socketId: 's-b' });
        addToQueue({ userId: 'e', rating: 1210, socketId: 's-e' });

        const match = findMatch(a);
        assert.ok(match);
        assert.strictEqual(match.userId, 'e');
        clean(['a', 'b', 'e']);
      },
    },
    {
      name: 'self-match prevented and duplicate queue replaced',
      run: async () => {
        const self = addToQueue({ userId: 'self', rating: 1200, socketId: 's-1' });
        const selfMatch = findMatch(self);
        assert.strictEqual(selfMatch, null);

        const latest = addToQueue({ userId: 'self', rating: 1250, socketId: 's-2' });
        assert.strictEqual(latest.socketId, 's-2');
        clean(['self']);
      },
    },
    {
      name: 'empty queue and race-like behavior are safe',
      run: async () => {
        const race1 = addToQueue({ userId: 'race1', rating: 1300, socketId: 'rs1' });
        const none = findMatch(race1);
        assert.strictEqual(none, null);

        addToQueue({ userId: 'race2', rating: 1300, socketId: 'rs2' });
        const found = findMatch(race1);
        assert.ok(found);
        assert.strictEqual(found.userId, 'race2');

        removeFromQueue('race1');
        removeFromQueue('race2');
        const noAfterRemoval = findMatch(race1);
        assert.strictEqual(noAfterRemoval, null);
      },
    },
  ]);

  clean(ids);
}

if (require.main === module) {
  run().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = { run };
