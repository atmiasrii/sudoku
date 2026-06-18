-- Supabase Realtime setup for live profile/leaderboard updates
-- Run this once via the Supabase SQL editor (use service-role or admin key)
-- The Flutter client (with anon key) will be able to subscribe to changes
-- after this publication is enabled.
--
-- This script is idempotent: safe to re-run. Postgres has no
-- "CREATE POLICY IF NOT EXISTS", so each policy is dropped first, and each
-- publication ADD is guarded against the table already being a member.

-- Enable Realtime change feed for live profile updates.
-- ALTER PUBLICATION ... ADD TABLE errors if the table is already a member, so
-- only add when missing.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public' AND tablename = 'users'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.users;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public' AND tablename = 'games'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.games;
  END IF;
END
$$;

-- RLS: Allow clients to receive Realtime events for rows they can SELECT.
-- Adjust these policies to match your existing RLS rules if users/games already
-- have RLS enabled with different logic.

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_all" ON public.users;
CREATE POLICY "users_select_all" ON public.users
  FOR SELECT USING (true);

ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "games_select_own" ON public.games;
CREATE POLICY "games_select_own" ON public.games
  FOR SELECT USING (
    auth.uid() = player1_id OR auth.uid() = player2_id
  );
