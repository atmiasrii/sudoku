const supabase = require('../config/supabase');

// Public, non-PII columns only. Never select('*') on a service-role client:
// it would leak any sensitive column (e.g. email) to anyone hitting the API.
const PUBLIC_COLUMNS = 'id, username, rating, games_played, wins, losses';

// Postgres unique-violation SQLSTATE.
const UNIQUE_VIOLATION = '23505';

async function insertUserProfile(userId, username) {
  return supabase
    .from('users')
    .insert({
      id: userId,
      username,
      rating: 1200,
      games_played: 0,
      wins: 0,
      losses: 0,
    })
    .select(PUBLIC_COLUMNS)
    .single();
}

// Creates the profile row. On a username collision: when [allowSuffix] is set
// (the login auto-derive path, which must never hard-fail) retry once with a
// random numeric suffix; otherwise surface a 'username_taken' error so explicit
// signup can reject it.
async function createUserProfile(userId, username, { allowSuffix = false } = {}) {
  let { data, error } = await insertUserProfile(userId, username);

  if (error && error.code === UNIQUE_VIOLATION) {
    // The id is the primary key, so a 23505 can be either "profile exists"
    // (same id) or "username taken".
    const isIdCollision = /\bid\b/i.test(error.message || '');
    if (isIdCollision) {
      // This authed user already has a profile — that's success, not an error.
      // Return the existing row so signup/login resolve cleanly (no scary
      // "duplicate key" log, no confusing client error).
      return getUserById(userId);
    }

    // Otherwise it's a username clash.
    if (allowSuffix) {
      const suffixed = `${username}_${Math.floor(1000 + Math.random() * 9000)}`;
      ({ data, error } = await insertUserProfile(userId, suffixed));
    } else {
      throw new Error('username_taken');
    }
  }

  if (error) {
    throw new Error(`Failed to create user profile: ${error.message}`);
  }

  return data;
}

// True when no existing user (case-insensitive) already has this username.
// `_` and `%` are LIKE wildcards, so escape them for an exact ilike match.
async function isUsernameAvailable(username) {
  const pattern = username.replace(/([\\%_])/g, '\\$1');
  const { data, error } = await supabase
    .from('users')
    .select('id')
    .ilike('username', pattern)
    .limit(1);

  if (error) {
    throw new Error(`Failed to check username: ${error.message}`);
  }

  return data.length === 0;
}

async function getUserById(userId) {
  const { data, error } = await supabase
    .from('users')
    .select(PUBLIC_COLUMNS)
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

// Atomic delta update via RPC (not a plain SET rating = X): a bot user row
// can be in several concurrent matches at once, so a read-then-write from the
// app would race and silently drop a delta when two finish close together.
async function incrementUserRating(userId, delta) {
  const { error } = await supabase.rpc('increment_user_rating', {
    p_user_id: userId,
    p_delta: delta,
  });

  if (error) {
    throw new Error(`Failed to update user rating: ${error.message}`);
  }
}

async function getLeaderboard(limit = 10) {
  const normalizedLimit = Number.isInteger(Number(limit)) ? Number(limit) : 10;

  const { data, error } = await supabase
    .from('users')
    .select(PUBLIC_COLUMNS)
    .order('rating', { ascending: false })
    .limit(Math.max(1, Math.min(100, normalizedLimit)));

  if (error) {
    throw new Error(`Failed to fetch leaderboard: ${error.message}`);
  }

  return data;
}

// The synthetic opponent pool for bot matches (see websocket/socketServer.js
// scheduleBotFallback). Queried fresh each time rather than cached, since a
// bot's rating moves after every match it plays and a stale snapshot would
// pick a worse-matched opponent.
async function getBotPool() {
  const { data, error } = await supabase
    .from('users')
    .select('id, username, rating')
    .eq('is_bot', true);

  if (error) {
    throw new Error(`Failed to fetch bot pool: ${error.message}`);
  }

  return data;
}

module.exports = {
  createUserProfile,
  isUsernameAvailable,
  getUserById,
  getUserRating,
  updateUserRating,
  incrementUserRating,
  getBotPool,
  getLeaderboard,
};
