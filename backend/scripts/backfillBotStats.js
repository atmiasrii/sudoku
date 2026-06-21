require('dotenv').config();

const supabase = require('../config/supabase');

// Gives each bot a plausible win/loss record correlated with its rating, so
// the rankings page ("N wins" under each name) looks like real players rather
// than 500 rows all showing 0 wins. Pure UPDATE on existing is_bot rows — no
// games-table inserts (bot profiles aren't reachable in-app, so fake match
// rows would only bloat the table without ever being seen).
//
// Idempotent by default: only touches bots that still have games_played = 0,
// so a re-run won't re-roll bots that were already backfilled. Pass --force
// to re-roll everyone.

const FORCE = process.argv.includes('--force');

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

// Higher rating -> higher win rate (0.30 at the bottom of the pool, ~0.72 at
// the top), plus a little per-bot noise so it isn't a perfectly smooth curve.
function winRateForRating(rating) {
  const base = 0.30 + (clamp(rating, 800, 2000) - 800) / 1200 * 0.40;
  const noise = (Math.random() - 0.5) * 0.08;
  return clamp(base + noise, 0.20, 0.78);
}

// Higher-rated bots have generally played more (they "climbed"), with a wide
// random spread so totals don't look templated.
function gamesForRating(rating) {
  const lean = (clamp(rating, 800, 2000) - 800) / 1200; // 0..1
  const min = 8 + Math.round(lean * 40);
  const max = 60 + Math.round(lean * 240);
  return min + Math.floor(Math.random() * (max - min + 1));
}

async function run() {
  let query = supabase
    .from('users')
    .select('id, rating, games_played')
    .eq('is_bot', true);

  if (!FORCE) {
    query = query.eq('games_played', 0);
  }

  const { data: bots, error } = await query;
  if (error) {
    throw new Error(`Failed to fetch bots: ${error.message}`);
  }

  if (!bots || bots.length === 0) {
    console.log(FORCE
      ? 'No bot users found.'
      : 'No bots with games_played = 0 to backfill (use --force to re-roll all).');
    return;
  }

  console.log(`Backfilling stats for ${bots.length} bots${FORCE ? ' (forced re-roll)' : ''}.`);

  let updated = 0;
  const sample = [];

  for (const bot of bots) {
    const rating = Number(bot.rating ?? 1200);
    const games = gamesForRating(rating);
    const wins = Math.round(games * winRateForRating(rating));
    const losses = games - wins;

    const { error: updateError } = await supabase
      .from('users')
      .update({ games_played: games, wins, losses })
      .eq('id', bot.id);

    if (updateError) {
      console.error(`Failed to update bot ${bot.id}: ${updateError.message}`);
      continue;
    }

    updated += 1;
    if (sample.length < 5) sample.push({ rating, games, wins, losses });
    if (updated % 50 === 0) console.log(`Updated ${updated}/${bots.length}...`);
  }

  console.log(`Done. Updated ${updated} bots. Sample:`, sample);
}

run()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('backfillBotStats failed:', err.message);
    process.exit(1);
  });
