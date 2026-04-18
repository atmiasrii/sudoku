const supabase = require('../config/supabase');

async function createUserProfile(userId, username) {
  const { data, error } = await supabase
    .from('users')
    .insert({
      id: userId,
      username,
      rating: 1200,
      games_played: 0,
      wins: 0,
      losses: 0,
    })
    .select('*')
    .single();

  if (error) {
    throw new Error(`Failed to create user profile: ${error.message}`);
  }

  return data;
}

async function getUserById(userId) {
  const { data, error } = await supabase
    .from('users')
    .select('*')
    .eq('id', userId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to fetch user profile: ${error.message}`);
  }

  return data;
}

async function getUserRating(userId) {
  const { data, error } = await supabase
    .from('users')
    .select('rating')
    .eq('id', userId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to fetch user rating: ${error.message}`);
  }

  return data?.rating;
}

async function updateUserRating(userId, newRating) {
  const { data, error } = await supabase
    .from('users')
    .update({ rating: newRating })
    .eq('id', userId)
    .select('*')
    .single();

  if (error) {
    throw new Error(`Failed to update user rating: ${error.message}`);
  }

  return data;
}

async function getLeaderboard(limit = 10) {
  const normalizedLimit = Number.isInteger(Number(limit)) ? Number(limit) : 10;

  const { data, error } = await supabase
    .from('users')
    .select('*')
    .order('rating', { ascending: false })
    .limit(Math.max(1, Math.min(100, normalizedLimit)));

  if (error) {
    throw new Error(`Failed to fetch leaderboard: ${error.message}`);
  }

  return data;
}

module.exports = {
  createUserProfile,
  getUserById,
  getUserRating,
  updateUserRating,
  getLeaderboard,
};
