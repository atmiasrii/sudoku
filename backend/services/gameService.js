const supabase = require('../config/supabase');

async function getUserStats(userId) {
  const { data, error } = await supabase
    .from('users')
    .select('games_played, wins, losses')
    .eq('id', userId)
    .single();

  if (error) {
    throw new Error(`Failed to fetch user stats: ${error.message}`);
  }

  return data;
}

async function setUserStats(userId, stats) {
  const { error } = await supabase
    .from('users')
    .update(stats)
    .eq('id', userId);

  if (error) {
    throw new Error(`Failed to update user stats: ${error.message}`);
  }
}

async function updatePlayerStats(winnerId, loserId) {
  // Atomic in Postgres (see sql/rpc_functions.sql). Read-then-write here would
  // lose increments when two matches finish for the same user concurrently.
  const [winnerResult, loserResult] = await Promise.all([
    supabase.rpc('increment_user_stats', { p_user_id: winnerId, p_win: 1, p_loss: 0 }),
    supabase.rpc('increment_user_stats', { p_user_id: loserId, p_win: 0, p_loss: 1 }),
  ]);

  if (winnerResult.error) {
    throw new Error(`Failed to update winner stats: ${winnerResult.error.message}`);
  }
  if (loserResult.error) {
    throw new Error(`Failed to update loser stats: ${loserResult.error.message}`);
  }
}

// Increment a single player's win/loss. Used for bot matches, where the
// opponent has no `users` row (a non-uuid bot id) so the two-sided
// updatePlayerStats can't run.
async function updateSoloStats(userId, won) {
  const { error } = await supabase.rpc('increment_user_stats', {
    p_user_id: userId,
    p_win: won ? 1 : 0,
    p_loss: won ? 0 : 1,
  });

  if (error) {
    throw new Error(`Failed to update solo stats: ${error.message}`);
  }
}

async function storeMatchResult(matchData) {
  const {
    seed,
    player1_id: player1Id,
    player2_id: player2Id,
    winner_id: winnerId,
    duration = 0,
    mistakes = 0,
    rating_delta = 0,
  } = matchData;

  const { data, error } = await supabase
    .from('games')
    .insert({
      seed,
      player1_id: player1Id,
      player2_id: player2Id,
      winner_id: winnerId,
      duration,
      mistakes,
      rating_delta,
    })
    .select('*')
    .single();

  if (error) {
    throw new Error(`Failed to store match result: ${error.message}`);
  }

  if (winnerId && player1Id && player2Id) {
    const loserId = winnerId === player1Id ? player2Id : player1Id;
    await updatePlayerStats(winnerId, loserId);
  }

  return data;
}

async function getPlayerMatchHistory(userId) {
  const { data, error } = await supabase
    .from('games')
    .select('*')
    .or(`player1_id.eq.${userId},player2_id.eq.${userId}`)
    .order('created_at', { ascending: false });

  if (error) {
    throw new Error(`Failed to fetch player match history: ${error.message}`);
  }

  return data;
}

module.exports = {
  storeMatchResult,
  updatePlayerStats,
  updateSoloStats,
  getPlayerMatchHistory,
};
