const {
  createUserProfile,
  isUsernameAvailable,
  getUserById,
  getLeaderboard,
} = require('../services/userService');
const {
  isUuid,
  isUserId,
  sanitizeText,
  isValidUsername,
  clampInt,
} = require('../utils/validators');

async function createUserProfileController(req, res) {
  try {
    const { userId, username } = req.body || {};

    // When auth is enforced, bind the profile to the verified token id so a
    // caller can never create/impersonate a profile for someone else.
    const effectiveUserId = req.userId || userId;

    if (!effectiveUserId || !username) {
      return res.status(400).json({ message: 'userId and username are required' });
    }

    if (!isUuid(effectiveUserId)) {
      return res.status(400).json({ message: 'userId must be a valid UUID' });
    }

    if (req.userId && userId && userId !== req.userId) {
      return res.status(403).json({ message: 'Cannot create a profile for another user' });
    }

    const cleanUsername = sanitizeText(username, 24);
    if (!cleanUsername || !isValidUsername(cleanUsername)) {
      return res.status(400).json({
        message: 'Username must be 3-20 letters, numbers, _ . or -',
        code: 'invalid_username',
      });
    }

    // allowSuffix lets the login auto-derive path recover from a clash instead
    // of failing; explicit signup leaves it false so duplicates are rejected.
    const allowSuffix = req.body.allowSuffix === true;
    const profile = await createUserProfile(effectiveUserId, cleanUsername, {
      allowSuffix,
    });
    return res.status(201).json(profile);
  } catch (error) {
    console.error('createUserProfileController error:', error);
    if (error.message === 'username_taken') {
      return res.status(409).json({
        message: 'That username is already taken',
        code: 'username_taken',
      });
    }
    if (error.message && error.message.toLowerCase().includes('duplicate')) {
      return res.status(409).json({ message: 'User profile already exists' });
    }
    return res.status(500).json({ message: 'Failed to create user profile' });
  }
}

async function checkUsernameController(req, res) {
  try {
    const username = typeof req.query.username === 'string'
      ? sanitizeText(req.query.username, 24)
      : null;

    if (!username || !isValidUsername(username)) {
      return res.status(400).json({
        available: false,
        message: 'Username must be 3-20 letters, numbers, _ . or -',
        code: 'invalid_username',
      });
    }

    const available = await isUsernameAvailable(username);
    return res.json({ available });
  } catch (error) {
    console.error('checkUsernameController error:', error);
    return res.status(500).json({ message: 'Failed to check username' });
  }
}

async function getUserProfileController(req, res) {
  try {
    if (!isUserId(req.params.id)) {
      return res.status(400).json({ message: 'Invalid user id' });
    }

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
    const limit = clampInt(req.query.limit, 1, 100, 10);
    const leaderboard = await getLeaderboard(limit);
    return res.json({ players: leaderboard });
  } catch (error) {
    console.error('getLeaderboardController error:', error);
    return res.status(500).json({ message: 'Failed to fetch leaderboard' });
  }
}

module.exports = {
  createUserProfileController,
  checkUsernameController,
  getUserProfileController,
  getLeaderboardController,
};
