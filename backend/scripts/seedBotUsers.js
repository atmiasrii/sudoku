require('dotenv').config();

const crypto = require('crypto');
const supabase = require('../config/supabase');
const { isUsernameAvailable } = require('../services/userService');

const TARGET_COUNT = 500;
// 45% gamertag / 40% name-style / 15% word-combo.
const SPLIT = { gamertag: 225, nameStyle: 200, wordCombo: 75 };
const MAX_USERNAME_LEN = 20;
const FK_VIOLATION = '23503';
const UNIQUE_VIOLATION = '23505';

// --- Word banks -------------------------------------------------------------
// Sized generously relative to how many unique names each category needs, so
// per-row collision retries stay rare (two ~30-word banks only give 900
// pairs; these give well into the tens of thousands of combinations).

const GAMER_ADJECTIVES = [
  'Shadow', 'Toxic', 'Silent', 'Night', 'Epic', 'Savage', 'Frost', 'Cyber', 'Dark', 'Phantom',
  'Crimson', 'Rapid', 'Quantum', 'Iron', 'Steel', 'Venom', 'Rogue', 'Stealth', 'Blaze', 'Storm',
  'Arctic', 'Brutal', 'Chaos', 'Doom', 'Royal', 'Solar', 'Lunar', 'Cosmic', 'Mystic', 'Wicked',
  'Feral', 'Grim', 'Wild', 'Frozen', 'Burning', 'Electric', 'Atomic', 'Sonic', 'Turbo', 'Mega',
  'Hyper', 'Prime', 'Alpha', 'Omega', 'Static', 'Astro', 'Cobalt', 'Crimson2', 'Vicious', 'Lethal',
  'Fatal', 'Rabid', 'Sneaky', 'Swift', 'Nimble', 'Fearless', 'Reckless', 'Mighty', 'Furious', 'Vengeful',
  'Ruthless', 'Sinister', 'Bold', 'Daring', 'Cunning', 'Relentless', 'Savage2', 'Glacial', 'Radiant', 'Obsidian',
  'Crimson3', 'Emerald', 'Golden', 'Scarlet', 'Violet', 'Azure', 'Ashen', 'Spectral', 'Infernal', 'Celestial',
  'Rogue2', 'Phantom2', 'Toxic2', 'Neon', 'Plasma', 'Digital', 'Glitch', 'Binary', 'Vector', 'Pixel',
  'Crispy', 'Salty', 'Spicy', 'Frosty', 'Stormy', 'Windy', 'Foggy', 'Rusty', 'Dusty', 'Gritty',
];

const GAMER_NOUNS = [
  'Wolf', 'Ninja', 'Reaper', 'Phoenix', 'Viper', 'Falcon', 'Blade', 'Hunter', 'Ghost', 'Dragon',
  'Tiger', 'Hawk', 'Raven', 'Cobra', 'Panther', 'Knight', 'Samurai', 'Warlord', 'Titan', 'Sniper',
  'Assassin', 'Warrior', 'Gladiator', 'Berserker', 'Ranger', 'Rider', 'Slayer', 'Striker', 'Hunter2', 'Stalker',
  'Fox', 'Bear', 'Lion', 'Shark', 'Scorpion', 'Spider', 'Mantis', 'Lynx', 'Jaguar', 'Eagle',
  'Crow', 'Owl', 'Wraith', 'Specter', 'Demon', 'Golem', 'Goblin', 'Wizard', 'Mage', 'Sorcerer',
  'Paladin', 'Templar', 'Crusader', 'Marauder', 'Outlaw', 'Renegade', 'Vagabond', 'Nomad', 'Drifter', 'Phantom3',
  'Bandit', 'Pirate', 'Viking', 'Spartan', 'Gladius', 'Saber', 'Dagger', 'Arrow', 'Bullet', 'Cannon',
  'Comet', 'Meteor', 'Nova', 'Pulsar', 'Quasar', 'Vortex', 'Cyclone', 'Tornado', 'Tempest', 'Avalanche',
  'Inferno', 'Glacier', 'Volcano', 'Thunder', 'Lightning', 'Hurricane', 'Maverick', 'Rebel', 'Legend', 'Champion',
  'Hexbolt', 'Ironclad', 'Nightfall', 'Daybreak', 'Wraith2', 'Beast', 'Predator', 'Vulture', 'Jackal', 'Cheetah',
];

const FIRST_NAMES = [
  'Alex', 'Sam', 'Jordan', 'Taylor', 'Morgan', 'Casey', 'Riley', 'Jamie', 'Avery', 'Quinn',
  'Mike', 'Sarah', 'Chris', 'Emma', 'Ryan', 'Olivia', 'Daniel', 'Sophia', 'Mark', 'Grace',
  'James', 'Anna', 'Kevin', 'Laura', 'Brian', 'Hannah', 'Justin', 'Megan', 'Eric', 'Natalie',
  'Andrew', 'Rachel', 'Tyler', 'Jessica', 'Brandon', 'Ashley', 'Jason', 'Amanda', 'Nathan', 'Lauren',
  'Adam', 'Emily', 'Scott', 'Chloe', 'Paul', 'Victoria', 'Henry', 'Zoe', 'Sean', 'Maya',
  'Derek', 'Nicole', 'Aaron', 'Stephanie', 'Ian', 'Rebecca', 'Carlos', 'Maria', 'Luis', 'Sofia',
  'Diego', 'Camila', 'Mateo', 'Valentina', 'Hiro', 'Yuki', 'Kenji', 'Sakura', 'Wei', 'Mei',
  'Raj', 'Priya', 'Arjun', 'Anika', 'Omar', 'Layla', 'Ahmed', 'Fatima', 'Noah', 'Ella',
  'Lucas', 'Mia', 'Ethan', 'Ava', 'Logan', 'Isla', 'Owen', 'Ruby', 'Caleb', 'Hazel',
  'Felix', 'Nora', 'Leo', 'Iris', 'Max', 'June', 'Theo', 'Lily', 'Sam2', 'Robin',
];

const WORD_COMBO_ADJECTIVES = [
  'Purple', 'Sleepy', 'Tiny', 'Loud', 'Quiet', 'Fuzzy', 'Bouncy', 'Wobbly', 'Crunchy', 'Soggy',
  'Sparkly', 'Grumpy', 'Jolly', 'Lazy', 'Clumsy', 'Giggly', 'Squishy', 'Speckled', 'Dizzy', 'Chunky',
  'Breezy', 'Mellow', 'Plump', 'Stripy', 'Spotted', 'Curious', 'Tipsy', 'Wonky', 'Drowsy', 'Snug',
  'Velvet', 'Pickled', 'Toasty', 'Minty', 'Sunny', 'Misty', 'Rusty2', 'Dapper', 'Peculiar', 'Wandering',
  'Humble', 'Cheerful', 'Plucky', 'Soft', 'Round', 'Cozy', 'Tangled', 'Glowing', 'Floaty', 'Crispy2',
  'Doodle', 'Quirky', 'Pudgy', 'Mossy', 'Pebbly', 'Drowsy2', 'Skipping', 'Wiggly', 'Yawning', 'Snoozy',
];

const WORD_COMBO_NOUNS = [
  'Cactus', 'Toaster', 'Bicycle', 'Pickle', 'Octopus', 'Pancake', 'Walrus', 'Noodle', 'Pretzel', 'Penguin',
  'Waffle', 'Burrito', 'Hamster', 'Sandal', 'Teapot', 'Muffin', 'Sloth', 'Llama', 'Cupcake', 'Biscuit',
  'Raccoon', 'Otter', 'Beaver', 'Pumpkin', 'Acorn', 'Marble', 'Lantern', 'Umbrella', 'Sausage', 'Dumpling',
  'Mango', 'Coconut', 'Avocado', 'Cabbage', 'Turnip', 'Potato', 'Carrot', 'Lettuce', 'Cucumber', 'Radish',
  'Goose', 'Duckling', 'Tadpole', 'Snail', 'Ladybug', 'Firefly', 'Dandelion', 'Pinecone', 'Mushroom', 'Pebble',
  'Sock', 'Mitten', 'Beanie', 'Backpack', 'Kettle', 'Spatula', 'Whisk', 'Bucket', 'Wagon', 'Scooter',
];

const INITIALS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');

// --- Helpers -----------------------------------------------------------------

function pick(bank) {
  return bank[Math.floor(Math.random() * bank.length)];
}

function maybeDigits(probability, minDigits, maxDigits) {
  if (Math.random() >= probability) return '';
  const digits = minDigits + Math.floor(Math.random() * (maxDigits - minDigits + 1));
  const max = 10 ** digits - 1;
  return String(Math.floor(Math.random() * (max + 1)));
}

function genGamertag() {
  const base = Math.random() < 0.2
    ? `xX_${pick(GAMER_NOUNS)}_Xx`
    : `${pick(GAMER_ADJECTIVES)}${pick(GAMER_NOUNS)}`;
  return `${base}${maybeDigits(0.6, 1, 3)}`;
}

function genNameStyle() {
  const first = pick(FIRST_NAMES);
  const initial = pick(INITIALS).toLowerCase();
  const roll = Math.random();
  // Favor the "Hiro.M" firstname.initial look — that's the requested style.
  if (roll < 0.6) return `${first}.${initial}`;
  if (roll < 0.8) return `${first}_${initial}`;
  if (roll < 0.92) return `${first}${maybeDigits(1, 2, 2)}`;
  return first;
}

function genWordCombo() {
  const base = `${pick(WORD_COMBO_ADJECTIVES)}${pick(WORD_COMBO_NOUNS)}`;
  return `${base}${maybeDigits(0.4, 1, 2)}`;
}

const GENERATORS = {
  gamertag: genGamertag,
  nameStyle: genNameStyle,
  wordCombo: genWordCombo,
};

// Box-Muller — gives the leaderboard a natural-looking spread immediately
// instead of 500 identical 1200s.
function gaussianRating(mean = 1200, stdev = 150, min = 800, max = 2000) {
  let u = 0;
  let v = 0;
  while (u === 0) u = Math.random();
  while (v === 0) v = Math.random();
  const z = Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  return Math.round(Math.min(max, Math.max(min, mean + z * stdev)));
}

async function generateUniqueUsername(category, usedThisRun) {
  for (let attempt = 0; attempt < 30; attempt++) {
    const candidate = GENERATORS[category]();
    if (candidate.length < 3 || candidate.length > MAX_USERNAME_LEN) continue;
    const key = candidate.toLowerCase();
    if (usedThisRun.has(key)) continue;

    let available;
    try {
      available = await isUsernameAvailable(candidate);
    } catch (error) {
      console.error(`Username availability check failed for "${candidate}":`, error.message);
      continue;
    }
    if (!available) continue;

    usedThisRun.add(key);
    return candidate;
  }
  throw new Error(`Could not generate a unique "${category}" username after 30 attempts`);
}

// Tries a plain random uuid first (no Supabase Auth account). If `users.id`
// turns out to have a FK to auth.users, the first insert will fail with a
// foreign-key violation (23503) — in that case every bot identity needs a
// real (passwordless) Supabase Auth user minted first.
let fkConfirmedAbsent = null;

async function mintBotId() {
  if (fkConfirmedAbsent === false) {
    return mintViaAuthAdmin();
  }
  return crypto.randomUUID();
}

async function mintViaAuthAdmin() {
  const email = `bot_${crypto.randomUUID()}@bots.invalid`;
  const { data, error } = await supabase.auth.admin.createUser({
    email,
    email_confirm: true,
    password: crypto.randomUUID(),
  });
  if (error) {
    throw new Error(`Failed to mint auth user for bot: ${error.message}`);
  }
  return data.user.id;
}

async function insertBotRow(username, rating) {
  let id = await mintBotId();

  for (let attempt = 0; attempt < 2; attempt++) {
    const { error } = await supabase.from('users').insert({
      id,
      username,
      rating,
      is_bot: true,
      games_played: 0,
      wins: 0,
      losses: 0,
    });

    if (!error) {
      fkConfirmedAbsent = fkConfirmedAbsent === null ? true : fkConfirmedAbsent;
      return;
    }

    if (error.code === FK_VIOLATION && fkConfirmedAbsent !== false) {
      console.log('users.id has a foreign-key constraint to auth.users — minting real Auth users for the remaining bots.');
      fkConfirmedAbsent = false;
      id = await mintViaAuthAdmin();
      continue;
    }

    const insertError = new Error(`Failed to insert bot "${username}": ${error.message}`);
    insertError.code = error.code;
    throw insertError;
  }

  throw new Error(`Failed to insert bot "${username}" after retrying with a minted auth user`);
}

async function run() {
  const { count, error: countError } = await supabase
    .from('users')
    .select('id', { count: 'exact', head: true })
    .eq('is_bot', true);

  if (countError) {
    throw new Error(`Failed to count existing bot users: ${countError.message}`);
  }

  const shortfall = TARGET_COUNT - (count || 0);
  if (shortfall <= 0) {
    console.log(`Already have ${count} bot users (>= ${TARGET_COUNT}) — nothing to do.`);
    return;
  }

  console.log(`${count || 0} bot users exist, seeding ${shortfall} more to reach ${TARGET_COUNT}.`);

  // Scale today's shortfall proportionally across the three categories so a
  // partial re-run still ends up close to the intended 45/40/15 split.
  const plan = [
    ...Array(Math.round(shortfall * (SPLIT.gamertag / TARGET_COUNT))).fill('gamertag'),
    ...Array(Math.round(shortfall * (SPLIT.nameStyle / TARGET_COUNT))).fill('nameStyle'),
    ...Array(Math.round(shortfall * (SPLIT.wordCombo / TARGET_COUNT))).fill('wordCombo'),
  ].slice(0, shortfall);

  const usedThisRun = new Set();
  let inserted = 0;
  const sample = [];

  for (const category of plan) {
    const username = await generateUniqueUsername(category, usedThisRun);
    const rating = gaussianRating();

    try {
      await insertBotRow(username, rating);
      inserted += 1;
      if (sample.length < 5) sample.push({ username, rating });
      if (inserted % 50 === 0) console.log(`Inserted ${inserted}/${plan.length}...`);
    } catch (error) {
      // A username collision against a row inserted moments ago by this same
      // run (race-free here since we await sequentially, but cheap insurance)
      // — regenerate and retry once rather than aborting the whole batch.
      if (error.code === UNIQUE_VIOLATION) {
        const retryUsername = await generateUniqueUsername(category, usedThisRun);
        await insertBotRow(retryUsername, rating);
        inserted += 1;
        continue;
      }
      throw error;
    }
  }

  console.log(`Done. Inserted ${inserted} bot users. Sample:`, sample);
}

module.exports = {
  TARGET_COUNT,
  SPLIT,
  MAX_USERNAME_LEN,
  GENERATORS,
  gaussianRating,
  generateUniqueUsername,
};

// Only seed when invoked directly — requiring this file (e.g. from the
// rebalance script to reuse the generators) must not kick off a seed.
if (require.main === module) {
  run()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error('seedBotUsers failed:', error.message);
      process.exit(1);
    });
}
