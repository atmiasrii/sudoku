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
} = require('../controllers/gameController');

const router = express.Router();

router.get('/game/new', newGame);
router.get('/puzzle', getPuzzle);
router.post('/game/validate', validateMove);
router.post('/validate', validateBoard);
router.post('/game/check', checkGame);
router.post('/game/hint', getHint);
router.post('/game/update', updateGameProgress);
router.post('/sessions', createMatchSession);
router.get('/sessions/:gameId', getMatchSession);
router.patch('/sessions/:gameId/progress', updateMatchSessionProgress);
router.post('/sessions/:gameId/finish', finishMatchSession);
router.post('/games', storeMatchResultController);

module.exports = router;
