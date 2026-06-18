-- Atomic player-stat increment used after a match (services/gameService.js ->
-- updatePlayerStats). Doing this in the DB avoids lost updates when two matches
-- finish for the same user concurrently. Without this function every match
-- logs "Failed to update winner/loser stats" and games_played/wins/losses on
-- the users table never move (so the leaderboard shows 0 wins for everyone).
--
-- Run once in the Supabase SQL editor.

create or replace function public.increment_user_stats(
  p_user_id uuid,
  p_win integer,
  p_loss integer
)
returns void
language sql
as $$
  update public.users
  set games_played = coalesce(games_played, 0) + 1,
      wins         = coalesce(wins, 0) + p_win,
      losses       = coalesce(losses, 0) + p_loss
  where id = p_user_id;
$$;

-- Let the service-role backend call it.
grant execute on function public.increment_user_stats(uuid, integer, integer) to service_role;

-- Refresh PostgREST's schema cache so the RPC is callable immediately.
NOTIFY pgrst, 'reload schema';
