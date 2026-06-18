# Security Audit & Hardening

Audit of the Sudoku backend (Express + Socket.io + Supabase). Below: risks found
and what was changed. Date: 2026-06-14.

## Summary

13 issues found and fixed. Backend now boots clean with 0 npm vulnerabilities,
security headers, a CORS allowlist, global rate limiting, input validation on
every id/name/number, PII-safe DB selects, and a working (pinned-algorithm) auth
layer for both REST and WebSocket.

## Findings & Fixes

| # | Risk | Severity | Fix |
|---|------|----------|-----|
| 1 | CORS wildcard (`origin:'*'`) on Express + Socket.io — any site could drive the API with a victim's session | High | Env-driven allowlist (`CORS_ORIGINS`); no wildcard; rejects unknown origins with 403 |
| 2 | Auth disabled AND broken — `socketAuth` imported but never exported (`io.use(undefined)`); client `userId` blindly trusted | High | `socketAuth` implemented + exported; JWT pinned to HS256; verified id stored server-side and trusted over payloads |
| 3 | Account takeover via `POST /api/users` — anyone could create a profile for an arbitrary `userId` | High | UUID validation + ownership check (when auth on, profile bound to token id; mismatch → 403) |
| 4 | Match-result injection — `POST /api/games`, session finish/progress accepted arbitrary `winnerId`, unauthenticated | High | `requireAuth` on those routes; `winnerId` must be a participant; reporter must be a participant; player can only update own progress |
| 5 | No input validation — `userId`/`username` unbounded & unsanitized (stored-XSS + payload DoS) | Medium | `validators.js`: `isUserId`, `sanitizeText` (strips control + markup chars, length-clamped) |
| 6 | No REST rate limiting — DoS via puzzle gen / scraping | Medium | `express-rate-limit`: 120 req/min/IP global |
| 7 | No request body size limit | Medium | `express.json({ limit: '64kb' })` |
| 8 | No security headers (clickjacking, MIME sniff) | Medium | `helmet` (X-Frame-Options, nosniff, HSTS, …); `x-powered-by` disabled |
| 9 | `/ws-test` debug socket console exposed in all envs | Medium | Gated behind `EXPOSE_WS_TEST=true` (off by default) |
| 10 | PII disclosure — `select('*')` on service-role client returned every column (incl. email) | Medium | Explicit public-column allowlist in `userService` |
| 11 | `jsonwebtoken` not installed — enabling auth would crash the server | Medium | Dependency added |
| 12 | NaN injection — `Number(req.query.seed/limit)` unguarded | Low | `clampInt` with bounded fallbacks |
| 13 | Vulnerable transitive deps (path-to-regexp ReDoS [high], ws memory disclosure, qs DoS, uuid) | High/Med | `npm audit fix` → 0 vulnerabilities |

## How to enable production auth

1. Set `SUPABASE_JWT_SECRET` (Supabase Dashboard → Settings → API → JWT Secret).
2. Set `CORS_ORIGINS` to your real web-client origin(s).
3. Leave `EXPOSE_WS_TEST` unset/false.
4. Flutter/web client must send the Supabase access token:
   - REST: `Authorization: Bearer <token>`
   - Socket.io: `io(url, { auth: { token } })`

## Verified

- `npm audit` → 0 vulnerabilities
- Server boots clean on a temp port
- Helmet headers present; evil origin → 403; `/ws-test` → 404; invalid user id → 400

## Residual notes (not code bugs)

- The Flutter **anon/publishable** key in `lib/config/supabase_config.dart` is
  designed to be public — it is safe to ship *provided Supabase Row Level
  Security is enabled* on all tables (`backend/sql/realtime_setup.sql` enables
  RLS for `users`/`games`). The **service-role** key stays server-side only
  (`.env`, git-ignored).
- Consider per-route rate limits (tighter on `POST /api/games`) if abuse appears.
