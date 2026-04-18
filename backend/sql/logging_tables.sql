-- Supabase logging schema for Sudoku multiplayer backend

create table if not exists public.match_logs (
  id uuid primary key default gen_random_uuid(),
  game_id text not null,
  player1_id uuid,
  player2_id uuid,
  winner_id uuid,
  loser_id uuid,
  duration int,
  reason text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.suspicious_activity (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  game_id text,
  reason text not null,
  details jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.disconnect_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  game_id text,
  type text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.error_logs (
  id uuid primary key default gen_random_uuid(),
  message text not null,
  stack text,
  context jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.queue_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  joined_at timestamptz,
  matched_at timestamptz,
  wait_time int,
  created_at timestamptz not null default now()
);
