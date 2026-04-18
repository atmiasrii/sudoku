const assert = require('assert');

async function runSuite(suiteName, tests) {
  console.log(`\n[SUITE] ${suiteName}`);
  for (const testCase of tests) {
    const started = Date.now();
    try {
      await testCase.run();
      const elapsed = Date.now() - started;
      console.log(`  [PASS] ${testCase.name} (${elapsed}ms)`);
    } catch (error) {
      console.error(`  [FAIL] ${testCase.name}`);
      console.error(`         ${error && error.stack ? error.stack : error}`);
      throw error;
    }
  }
}

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

module.exports = {
  assert,
  runSuite,
  deepClone,
  delay,
};
