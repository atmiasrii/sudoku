-- Enforces case-insensitive unique usernames on public.users. Without this two
-- accounts could register the same display name (the backend only sanitized the
-- string, never checked uniqueness).
--
-- Run once in the Supabase SQL editor.
--
-- NOTE: if duplicate usernames already exist, the index creation below will
-- fail. Run the optional dedup block first to suffix the duplicates, then
-- create the index.

-- ── Optional dedup (run only if the index creation reports a duplicate) ──
-- Appends a short random suffix to all but the oldest row of each colliding
-- (case-insensitive) username so the unique index can be created.
--
-- WITH ranked AS (
--   SELECT id,
--          row_number() OVER (PARTITION BY lower(username) ORDER BY created_at) AS rn
--   FROM public.users
-- )
-- UPDATE public.users u
-- SET username = u.username || '_' || floor(random() * 9000 + 1000)::int
-- FROM ranked r
-- WHERE u.id = r.id AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS users_username_lower_key
  ON public.users (lower(username));
