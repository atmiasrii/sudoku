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
  const winnerStats = await getUserStats(winnerId);
  await setUserStats(winnerId, {
    wins: (winnerStats?.wins || 0) + 1,
    games_played: (winnerStats?.games_played || 0) + 1,
  });

  const loserStats = await getUserStats(loserId);
  await setUserStats(loserId, {
    losses: (loserStats?.losses || 0) + 1,
    games_played: (loserStats?.games_played || 0) + 1,
  });
}

async function storeMatchResult(matchData) {
  const {
    seed,
    player1_id: player1Id,
    player2_id: player2Id,
    winner_id: winnerId,
    duration = 0,
    mistakes = 0,
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
  getPlayerMatchHistory,
};
