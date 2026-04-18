require('dotenv').config();

const { probeLoggingTables } = require('../services/logService');

async function run() {
  const result = await probeLoggingTables();

  console.log('Logging enabled:', result.enabled);
  if (result.missing.length === 0) {
    console.log('All logging tables are available.');
    process.exit(0);
  }

  console.log('Missing or inaccessible logging tables:');
  for (const table of result.missing) {
    console.log(`- ${table}`);
  }

  console.log('\nDetails:');
  for (const row of result.details) {
    console.log(`${row.table}: ${row.ok ? 'OK' : `ERROR: ${row.message}`}`);
  }

  process.exit(1);
}

run().catch((error) => {
  console.error('checkLoggingTables failed:', error.message);
  process.exit(1);
});
