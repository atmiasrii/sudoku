// Eastern Time (America/New_York) date helpers for the daily challenge.
// ET ownership lives here so the daily puzzle rotates on the ET calendar
// boundary regardless of server/client timezone, and DST is handled by ICU.

const ET_ZONE = 'America/New_York';

// 'en-CA' formats as YYYY-MM-DD, which sorts and parses cleanly.
const _dateFmt = new Intl.DateTimeFormat('en-CA', {
  timeZone: ET_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

/** Current ET calendar date as 'YYYY-MM-DD'. */
function etDateString(now = new Date()) {
  return _dateFmt.format(now);
}

/** Deterministic integer seed for a date string, e.g. '2026-06-15' -> 20260615. */
function etSeedForDate(dateStr) {
  return Number(dateStr.replace(/-/g, ''));
}

/** Whole days since the Unix epoch for a 'YYYY-MM-DD' string — a stable "Daily #N". */
function etDayNumber(dateStr) {
  // Parse as a UTC midnight instant; only the day count matters, not the zone.
  const ms = Date.parse(`${dateStr}T00:00:00Z`);
  return Math.floor(ms / 86400000);
}

/**
 * Next ET-midnight as a UTC ISO timestamp. ET midnight is the first instant
 * whose ET calendar date differs from `now`'s. Coarse 15-minute steps locate
 * the boundary day, then 1-minute steps pin the exact minute — DST-safe with no
 * hardcoded offset. (Called rarely: the daily session is cached per ET date.)
 */
function nextEtMidnightUtcIso(now = new Date()) {
  const startDate = etDateString(now);
  let cursor = new Date(now.getTime());

  // Coarse pass: jump to just past the date change (≤ ~100 iterations).
  while (etDateString(cursor) === startDate) {
    cursor = new Date(cursor.getTime() + 15 * 60000);
  }
  // Fine pass: back up one coarse step, advance a minute at a time to the
  // first minute of the new ET day.
  cursor = new Date(cursor.getTime() - 15 * 60000);
  while (etDateString(cursor) === startDate) {
    cursor = new Date(cursor.getTime() + 60000);
  }
  // Floor to the minute so the timestamp is exactly ET midnight.
  cursor = new Date(Math.floor(cursor.getTime() / 60000) * 60000);
  return cursor.toISOString();
}

module.exports = {
  ET_ZONE,
  etDateString,
  etSeedForDate,
  etDayNumber,
  nextEtMidnightUtcIso,
};
