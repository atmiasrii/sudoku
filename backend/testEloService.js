const { calculateElo } = require('./services/eloService');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function run() {
  const equalWin = calculateElo(1200, 1200, 1);
  const equalLoss = calculateElo(1200, 1200, 0);
  const upsetWin = calculateElo(1200, 1400, 1);
  const expectedWin = calculateElo(1400, 1200, 1);
  const upsetGain = upsetWin - 1200;
  const expectedGain = expectedWin - 1400;

  assert(equalWin > 1200, 'Winning should increase rating');
  assert(equalLoss < 1200, 'Losing should decrease rating');
  assert(upsetWin > equalWin, 'Winning against stronger player should gain more');
  assert(expectedGain < upsetGain, 'Winning as favorite should gain less than upset win');

  console.log('ELO service checks passed');
}

run();
