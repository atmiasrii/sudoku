const {
  createSession,
  getSession,
  updateProgress,
  finishSession,
} = require('./services/gameSessionService');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function run() {
  const session = createSession('user1', 'user2');
  assert(session.status === 'active', 'New session status should be active');

  updateProgress(session.gameId, 'user1', { filledCells: 30 });
  const persisted = getSession(session.gameId);
  console.log('Session after update:', persisted);

  assert(!!persisted, 'Session should persist in memory');
  assert(persisted.status === 'active', 'Persisted session should remain active');
  assert(
    persisted.progress.user1.filledCells === 30,
    'Progress should update for user1',
  );

  const invalidCompletion = updateProgress(session.gameId, 'user1', {
    completed: true,
    board: Array.from({ length: 9 }, () => Array(9).fill(0)),
  });

  assert(invalidCompletion.error === 'Invalid solution', 'Wrong completed board should be rejected');
  assert(!!getSession(session.gameId), 'Session should continue after invalid completion');

  const solvedBoard = getSession(session.gameId).solution;
  const finishedByCompletion = updateProgress(session.gameId, 'user1', {
    completed: true,
    board: solvedBoard,
  });
  const deletedAfterAutoWin = getSession(session.gameId);

  assert(!!finishedByCompletion, 'Auto-finished session payload should be returned');
  assert(finishedByCompletion.status === 'finished', 'Auto-finished session should be marked finished');
  assert(finishedByCompletion.winnerId === 'user1', 'Auto-win should set winner to playerId');
  assert(finishedByCompletion.loserId === 'user2', 'Auto-win should set loserId');
  assert(deletedAfterAutoWin === undefined, 'Session should be deleted after auto-finish');

  const manualSession = createSession('user1', 'user2');
  const finished = finishSession(manualSession.gameId, 'user2');
  const deleted = getSession(manualSession.gameId);

  assert(!!finished, 'Manual finished session payload should be returned');
  assert(finished.status === 'finished', 'Manual finished session should be marked finished');
  assert(finished.winnerId === 'user2', 'Manual finish should capture winner');
  assert(finished.loserId === 'user1', 'Manual finish should capture loserId');
  assert(deleted === undefined, 'Session should be deleted after manual finish');

  console.log('All gameSessionService checks passed');
}

run();
