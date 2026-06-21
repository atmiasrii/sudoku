-- Run manually in the Supabase SQL Editor (no DDL execution path from the app/service-role REST client).
-- Replaces the fragile `userId.startsWith('bot_')` check with a real, format-independent flag.
alter table public.users add column if not exists is_bot boolean not null default false;
create index if not exists idx_users_is_bot on public.users (is_bot) where is_bot = true;
