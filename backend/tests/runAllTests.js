const path = require('path');

const suites = [
  './sudoku.test',
  './session.test',
  './matchmaking.test',
  './elo.test',
  './websocket.test',
  './antiCheat.test',
  './reconnect.test',
  './integration.test',
];

async function runAll() {
  const started = Date.now();
  const results = [];

  for (const suite of suites) {
    const suitePath = path.resolve(__dirname, suite);
    const suiteModule = require(suitePath);
    const name = path.basename(suite, '.test');

    const suiteStart = Date.now();
    try {
      await suiteModule.run();
      results.push({ name, status: 'pass', ms: Date.now() - suiteStart });
    } catch (error) {
      results.push({ name, status: 'fail', ms: Date.now() - suiteStart, error: error.message });
      break;
    }
  }

  console.log('\n=== TEST SUMMARY ===');
  for (const result of results) {
    const line = `${result.status.toUpperCase()} ${result.name} (${result.ms}ms)`;
    console.log(line);
    if (result.error) {
      console.log(`  error: ${result.error}`);
    }
  }

  const hasFailure = results.some((r) => r.status === 'fail');
  const total = Date.now() - started;
  console.log(`Total: ${total}ms`);

  if (hasFailure) {
    process.exit(1);
  }
}

runAll().catch((error) => {
  console.error(error);
  process.exit(1);
});
