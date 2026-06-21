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

-- Atomic rating delta (services/userService.js -> incrementUserRating). A bot
-- user row can be "in" several concurrent matches at once (it isn't a real
-- connected socket holding a single session), so a plain `SET rating = X`
-- read-then-write from the app would race and silently drop a delta when two
-- of its matches finish close together. This makes the write itself atomic.
create or replace function public.increment_user_rating(
  p_user_id uuid,
  p_delta integer
)
returns void
language sql
as $$
  update public.users
  set rating = coalesce(rating, 1200) + p_delta
  where id = p_user_id;
$$;

grant execute on function public.increment_user_rating(uuid, integer) to service_role;

-- Refresh PostgREST's schema cache so the RPCs are callable immediately.
NOTIFY pgrst, 'reload schema';
