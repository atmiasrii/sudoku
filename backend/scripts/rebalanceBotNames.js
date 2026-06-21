require('dotenv').config();

const supabase = require('../config/supabase');
const { SPLIT, TARGET_COUNT, generateUniqueUsername } = require('./seedBotUsers');

// One-time rebalance: the 500 bots were seeded under an older 65/20/15 split.
// This renames every existing bot in place to match the current SPLIT
// (45% gamertag / 40% name-style / 15% word-combo) — keeping each bot's id,
// rating, and win/loss stats untouched, only changing the username. Safe to
// re-run (it just re-rolls names to the same target distribution).

function shuffle(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

async function run() {
  const { data: bots, error } = await supabase
    .from('users')
    .select('id')
    .eq('is_bot', true);

  if (error) {
    throw new Error(`Failed to fetch bots: ${error.message}`);
  }

  if (!bots || bots.length === 0) {
    console.log('No bot users to rebalance.');
    return;
  }

  const total = bots.length;
  // Scale the configured split to however many bots actually exist, so this
  // works whether the pool is exactly 500 or some other count.
  const nGamertag = Math.round(total * (SPLIT.gamertag / TARGET_COUNT));
  const nNameStyle = Math.round(total * (SPLIT.nameStyle / TARGET_COUNT));
  const categories = [
    ...Array(nGamertag).fill('gamertag'),
    ...Array(nNameStyle).fill('nameStyle'),
  ];
  while (categories.length < total) categories.push('wordCombo');
  categories.length = total;
  shuffle(categories);

  console.log(`Rebalancing ${total} bots -> ${nGamertag} gamertag / ${nNameStyle} name-style / ${total - nGamertag - nNameStyle} word-combo.`);

  const usedThisRun = new Set();
  let updated = 0;
  const sample = [];

  for (let i = 0; i < bots.length; i++) {
    const category = categories[i];
    const username = await generateUniqueUsername(category, usedThisRun);

    const { error: updateError } = await supabase
      .from('users')
      .update({ username })
      .eq('id', bots[i].id);

    if (updateError) {
      console.error(`Failed to rename bot ${bots[i].id}: ${updateError.message}`);
      continue;
    }

    updated += 1;
    if (sample.length < 8) sample.push({ category, username });
    if (updated % 50 === 0) console.log(`Renamed ${updated}/${total}...`);
  }

  console.log(`Done. Renamed ${updated} bots. Sample:`, sample);
}

run()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('rebalanceBotNames failed:', err.message);
    process.exit(1);
  });
