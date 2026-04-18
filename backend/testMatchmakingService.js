const {
  addToQueue,
  findMatch,
  removeFromQueue,
} = require('./services/matchmakingService');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function nowMinus(seconds) {
  return Date.now() - (seconds * 1000);
}

function run() {
  removeFromQueue('p1200');
  removeFromQueue('p1250');
  removeFromQueue('p1600');

  const p1200 = addToQueue({ userId: 'p1200', rating: 1200, socketId: 's1', joinedAt: nowMinus(0) });
  const selfMatch = findMatch(p1200);
  assert(!selfMatch, 'Player must never match with themselves');

  addToQueue({ userId: 'p1250', rating: 1250, socketId: 's2', joinedAt: nowMinus(0) });

  const closeMatch = findMatch(p1200);
  assert(closeMatch && closeMatch.userId === 'p1250', '1200 should match 1250 in initial range');

  removeFromQueue('p1250');
  addToQueue({ userId: 'p1600', rating: 1600, socketId: 's3', joinedAt: nowMinus(0) });

  const noImmediateMatch = findMatch(p1200);
  assert(!noImmediateMatch, '1200 should not immediately match 1600');

  removeFromQueue('p1200');
  const waiting1200 = addToQueue({ userId: 'p1200', rating: 1200, socketId: 's1', joinedAt: nowMinus(16) });
  const expandedMatch = findMatch(waiting1200);
  assert(expandedMatch && expandedMatch.userId === 'p1600', '1200 should match 1600 after wait expansion');

  removeFromQueue('p1200');
  removeFromQueue('p1600');
  console.log('Matchmaking service checks passed');
}

run();
