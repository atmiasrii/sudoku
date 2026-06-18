const express = require('express');
const {
  newGame,
  getPuzzle,
  validateMove,
  validateBoard,
  checkGame,
  getHint,
  updateGameProgress,
  createMatchSession,
  getMatchSession,
  updateMatchSessionProgress,
  finishMatchSession,
  storeMatchResultController,
  dailyChallenge,
} = require('../controllers/gameController');
const { requireAuth } = require('../middleware/auth');
const { puzzleLimiter, matchWriteLimiter } = require('../middleware/rateLimiters');

const router = express.Router();

router.get('/game/new', puzzleLimiter, newGame);
router.get('/puzzle', puzzleLimiter, getPuzzle);
router.get('/daily', puzzleLimiter, dailyChallenge);
router.post('/game/validate', validateMove);
router.post('/validate', validateBoard);
router.post('/game/check', checkGame);
router.post('/game/hint', getHint);
router.post('/game/update', updateGameProgress);
// State-changing / result-recording routes require a valid token when auth is on.
router.post('/sessions', requireAuth, matchWriteLimiter, createMatchSession);
router.get('/sessions/:gameId', getMatchSession);
router.patch('/sessions/:gameId/progress', requireAuth, matchWriteLimiter, updateMatchSessionProgress);
router.post('/sessions/:gameId/finish', requireAuth, matchWriteLimiter, finishMatchSession);
router.post('/games', requireAuth, matchWriteLimiter, storeMatchResultController);

module.exports = router;
