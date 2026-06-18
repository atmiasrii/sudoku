-- Adds the rating_delta column the backend writes when storing a match result
-- (see services/gameService.js -> storeMatchResult). Without it every match
-- insert fails with "Could not find the 'rating_delta' column of 'games'",
-- so no games rows are saved and profile/home history stay empty.
--
-- Run once in the Supabase SQL editor.

ALTER TABLE public.games
  ADD COLUMN IF NOT EXISTS rating_delta integer NOT NULL DEFAULT 0;

-- Force PostgREST (the REST/schema layer the service-role client uses) to
-- refresh its cached schema so the new column is visible immediately.
NOTIFY pgrst, 'reload schema';
