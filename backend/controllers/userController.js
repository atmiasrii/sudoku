const {
  createUserProfile,
  getUserById,
  getLeaderboard,
} = require('../services/userService');

async function createUserProfileController(req, res) {
  try {
    const { userId, username } = req.body || {};

    if (!userId || !username) {
      return res.status(400).json({ message: 'userId and username are required' });
    }

    const profile = await createUserProfile(userId, username);
    return res.status(201).json(profile);
  } catch (error) {
    console.error('createUserProfileController error:', error);
    if (error.message && error.message.toLowerCase().includes('duplicate')) {
      return res.status(409).json({ message: 'User profile already exists' });
    }
    return res.status(500).json({ message: 'Failed to create user profile' });
  }
}

async function getUserProfileController(req, res) {
  try {
    const user = await getUserById(req.params.id);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }
    return res.json(user);
  } catch (error) {
    console.error('getUserProfileController error:', error);
    return res.status(500).json({ message: 'Failed to fetch user profile' });
  }
}

async function getLeaderboardController(req, res) {
  try {
    const limit = req.query.limit ? Number(req.query.limit) : 10;
    const leaderboard = await getLeaderboard(limit);
    return res.json({ players: leaderboard });
  } catch (error) {
    console.error('getLeaderboardController error:', error);
    return res.status(500).json({ message: 'Failed to fetch leaderboard' });
  }
}

module.exports = {
  createUserProfileController,
  getUserProfileController,
  getLeaderboardController,
};
