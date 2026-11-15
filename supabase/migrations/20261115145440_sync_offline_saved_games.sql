create table if not exists public.scrabble_saved_games (
  user_id uuid not null references auth.users(id) on delete cascade,
  game_key text not null check (game_key ~ '^(ar|en):(bot|local)$'),
  language text not null check (language in ('ar','en')),
  mode text not null check (mode in ('bot','local')),
  session jsonb not null check (jsonb_typeof(session)='object'),
  updated_at timestamptz not null default now(),
  primary key (user_id,game_key),
  check (split_part(game_key,':',1)=language and split_part(game_key,':',2)=mode)
);

alter table public.scrabble_saved_games enable row level security;
drop policy if exists "players manage own saved games" on public.scrabble_saved_games;
create policy "players manage own saved games"
  on public.scrabble_saved_games
  for all
  to authenticated
  using ((select auth.uid())=user_id)
  with check ((select auth.uid())=user_id);

grant select,insert,update,delete on public.scrabble_saved_games to authenticated;
