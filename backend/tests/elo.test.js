const { assert, runSuite } = require('./_runner');
const { calculateElo } = require('../services/eloService');

function computePair(a, b, winnerIsA) {
  const newA = calculateElo(a, b, winnerIsA ? 1 : 0);
  const newB = calculateElo(b, a, winnerIsA ? 0 : 1);
  return { newA, newB };
}

async function run() {
  await runSuite('ELO', [
    {
      name: 'equal ratings produce ~16 gain/loss',
      run: async () => {
        const { newA, newB } = computePair(1200, 1200, true);
        assert.strictEqual(newA, 1216);
        assert.strictEqual(newB, 1184);
      },
    },
    {
      name: 'upset win gives higher gain',
      run: async () => {
        const upset = computePair(1200, 1400, true);
        const expected = computePair(1400, 1200, true);
        const upsetGain = upset.newA - 1200;
        const expectedGain = expected.newA - 1400;
        assert.ok(upsetGain > expectedGain);
      },
    },
    {
      name: 'weaker-opponent loss yields larger penalty',
      run: async () => {
        const weakLoss = computePair(1400, 1200, false);
        const strongLoss = computePair(1200, 1400, false);

        const weakPenalty = 1400 - weakLoss.newA;
        const strongPenalty = 1200 - strongLoss.newA;
        assert.ok(weakPenalty > strongPenalty);
      },
    },
    {
      name: 'extreme rating gaps and rounding are stable',
      run: async () => {
        const high = computePair(2800, 800, true);
        const upset = computePair(800, 2800, true);

        assert.ok(Number.isInteger(high.newA));
        assert.ok(Number.isInteger(high.newB));
        assert.ok(Number.isInteger(upset.newA));
        assert.ok(Number.isInteger(upset.newB));

        assert.ok(high.newA >= 2800);
        assert.ok(upset.newA > 800);
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
