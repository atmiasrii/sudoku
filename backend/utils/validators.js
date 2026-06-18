// Shared input validation/sanitization helpers. Backend is the trust boundary:
// every id, name, and number arriving over HTTP/WebSocket is treated as hostile
// until it passes through here.

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isUuid(value) {
  return typeof value === 'string' && UUID_RE.test(value);
}

// Accept real Supabase user UUIDs and our internal bot ids ("bot_xxxx").
function isUserId(value) {
  if (typeof value !== 'string') return false;
  if (value.startsWith('bot_')) return value.length <= 40;
  return isUuid(value);
}

// Drop ASCII control chars (0x00-0x1F) and HTML-significant chars, then clamp
// length so a username can never carry markup into a web client or balloon a
// payload. Returns null if nothing usable survives.
function sanitizeText(value, maxLen = 32) {
  if (typeof value !== 'string') return null;
  let cleaned = '';
  for (const ch of value) {
    const code = ch.codePointAt(0);
    if (code < 0x20 || code === 0x7f) continue; // control chars
    if ('<>&"\'`'.includes(ch)) continue; // markup-significant
    cleaned += ch;
  }
  cleaned = cleaned.trim().slice(0, maxLen);
  return cleaned.length > 0 ? cleaned : null;
}

// Username format: 3-20 chars, letters/digits/underscore/dot/hyphen only.
// Uniqueness is enforced separately by a case-insensitive DB index.
const USERNAME_RE = /^[A-Za-z0-9_.-]{3,20}$/;

function isValidUsername(value) {
  return typeof value === 'string' && USERNAME_RE.test(value);
}

// Coerce to a bounded integer; returns fallback for NaN/out-of-range input.
function clampInt(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  const i = Math.trunc(n);
  if (i < min) return min;
  if (i > max) return max;
  return i;
}

module.exports = { isUuid, isUserId, sanitizeText, isValidUsername, clampInt };
