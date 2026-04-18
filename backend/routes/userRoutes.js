const express = require('express');
const {
  createUserProfileController,
  getUserProfileController,
  getLeaderboardController,
} = require('../controllers/userController');
const { getMatchHistoryController } = require('../controllers/gameController');

const router = express.Router();

router.get('/leaderboard', getLeaderboardController);
router.get('/users/:id', getUserProfileController);
router.post('/users', createUserProfileController);
router.get('/users/:id/matches', getMatchHistoryController);

module.exports = router;
