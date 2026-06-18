const rateLimit = require('express-rate-limit');

// Global baseline: blunt protection against scraping/DoS on every route.
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Too many requests, slow down.' },
});

// Puzzle/board generation is CPU-heavier than a plain read — cap tighter than
// the global limit to blunt scripted scraping of fresh puzzles.
const puzzleLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Too many puzzle requests, slow down.' },
});

// Match-result / session-finish writes carry rating changes — keep these
// tighter than the global ceiling to blunt result-spam/rating manipulation.
const matchWriteLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Too many match updates, slow down.' },
});

// Account-creation attempts (POST /api/users). This endpoint is also hit on
// every sign-in (ensureUserProfile), which returns 409 once the profile
// exists — skipFailedRequests means only successful (201) profile creations
// count, so normal sign-ins are never throttled. Caps brute-force account
// enumeration/creation at 5 per 15 minutes per IP.
const accountCreationLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  skipFailedRequests: true,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Too many account creation attempts. Try again in 15 minutes.' },
});

module.exports = { apiLimiter, puzzleLimiter, matchWriteLimiter, accountCreationLimiter };
