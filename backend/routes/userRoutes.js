const express = require('express');
const {
  createUserProfileController,
  checkUsernameController,
  getUserProfileController,
  getLeaderboardController,
} = require('../controllers/userController');
const { getMatchHistoryController } = require('../controllers/gameController');
const { requireAuth } = require('../middleware/auth');
const { accountCreationLimiter } = require('../middleware/rateLimiters');

const router = express.Router();

router.get('/leaderboard', getLeaderboardController);
// Must precede '/users/:id' so it isn't captured as an id lookup.
router.get('/users/username-available', checkUsernameController);
router.get('/users/:id', getUserProfileController);
router.post('/users', accountCreationLimiter, requireAuth, createUserProfileController);
router.get('/users/:id/matches', getMatchHistoryController);

module.exports = router;
