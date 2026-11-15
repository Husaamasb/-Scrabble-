-- Scrabble cloud backend (Supabase / PostgreSQL)
-- Run this entire file in Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  public_id text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  username text not null check (char_length(username) between 2 and 20),
  bio text not null default '' check (char_length(bio) <= 120),
  privacy text not null default 'everyone' check (privacy in ('everyone','friends','private')),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists profiles_username_lower_idx on public.profiles (lower(username));

create or replace function public.create_profile_for_new_user()
returns trigger language plpgsql security definer set search_path = public
as $func$
declare desired_name text; candidate_name text;
begin
  desired_name := left(coalesce(nullif(trim(new.raw_user_meta_data->>'username'),''),split_part(new.email,'@',1)),20);
  if char_length(desired_name)<2 then desired_name := 'Player'; end if;
  candidate_name := desired_name;
  while exists(select 1 from public.profiles where lower(username)=lower(candidate_name)) loop
    candidate_name := left(desired_name,14) || substr(replace(gen_random_uuid()::text,'-',''),1,5);
  end loop;
  insert into public.profiles (id, username)
  values (new.id, candidate_name)
  on conflict (id) do nothing;
  return new;
end;
$func$;
drop trigger if exists on_auth_user_created_scrabble on auth.users;
create trigger on_auth_user_created_scrabble after insert on auth.users
for each row execute procedure public.create_profile_for_new_user();

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected','cancelled')),
  created_at timestamptz not null default now(),
  unique(sender_id, receiver_id),
  check(sender_id <> receiver_id)
);
create table if not exists public.friendships (
  user_low uuid not null references public.profiles(id) on delete cascade,
  user_high uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_low,user_high),
  check(user_low < user_high)
);

create or replace function public.accept_friend_request(request_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare req public.friend_requests;
begin
  select * into req from public.friend_requests where id=request_id and receiver_id=auth.uid() and status='pending' for update;
  if not found then raise exception 'Friend request not found'; end if;
  insert into public.friendships(user_low,user_high)
  values (least(req.sender_id,req.receiver_id),greatest(req.sender_id,req.receiver_id))
  on conflict do nothing;
  update public.friend_requests set status='accepted' where id=request_id;
end;
$$;

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default lpad((floor(random()*1000000))::int::text,6,'0'),
  name text not null check(char_length(name) between 2 and 40),
  host_id uuid not null references public.profiles(id) on delete cascade,
  is_public boolean not null default true,
  max_players int not null default 4 check(max_players between 2 and 4),
  language text not null default 'ar' check(language in ('ar','en')),
  status text not null default 'waiting' check(status in ('waiting','playing','finished')),
  game_state jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.room_members (
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  seat int not null check(seat between 1 and 4),
  is_ready boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key(room_id,user_id),
  unique(room_id,seat)
);
create table if not exists public.room_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check(char_length(content) between 1 and 1000),
  created_at timestamptz not null default now()
);
create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check(char_length(content) between 1 and 1000),
  created_at timestamptz not null default now(),
  check(sender_id <> recipient_id)
);
create table if not exists public.room_invites (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  check(sender_id <> receiver_id)
);

create or replace function public.join_room_by_code(room_code text)
returns uuid language plpgsql security definer set search_path = public
as $$
declare target public.rooms; next_seat int; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Sign in required'; end if;
  select * into target from public.rooms where code=room_code and status='waiting' for update;
  if not found then raise exception 'Room not found or already started'; end if;
  if exists(select 1 from public.room_members where room_id=target.id and user_id=uid) then return target.id; end if;
  select coalesce(max(seat),0)+1 into next_seat from public.room_members where room_id=target.id;
  if next_seat>target.max_players then raise exception 'Room is full'; end if;
  insert into public.room_members(room_id,user_id,seat) values(target.id,uid,next_seat);
  return target.id;
end;
$$;

create or replace function public.create_scrabble_room(room_name text, public_room boolean, player_limit int, game_language text)
returns setof public.rooms language plpgsql security definer set search_path = public
as $$
declare created public.rooms;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if player_limit not between 2 and 4 then raise exception 'Player limit must be 2 to 4'; end if;
  insert into public.rooms(name,host_id,is_public,max_players,language)
  values(left(room_name,40),auth.uid(),public_room,player_limit,game_language)
  returning * into created;
  insert into public.room_members(room_id,user_id,seat) values(created.id,auth.uid(),1);
  return next created;
end;
$$;

create or replace function public.is_scrabble_room_member(target_room uuid)
returns boolean language sql stable security definer set search_path = public
as $func$ select exists(select 1 from public.room_members where room_id=target_room and user_id=auth.uid()) $func$;

alter table public.profiles enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.room_messages enable row level security;
alter table public.direct_messages enable row level security;
alter table public.room_invites enable row level security;
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles, public.friend_requests, public.friendships, public.rooms, public.room_members, public.room_messages, public.direct_messages, public.room_invites to authenticated;

drop policy if exists "profiles readable by signed in users" on public.profiles;
create policy "profiles readable by privacy settings" on public.profiles for select to authenticated using (id=auth.uid() or privacy='everyone' or (privacy='friends' and exists(select 1 from public.friendships f where (f.user_low=auth.uid() and f.user_high=id) or (f.user_high=auth.uid() and f.user_low=id))));
drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());

drop policy if exists "friend requests visible to participants" on public.friend_requests;
create policy "friend requests visible to participants" on public.friend_requests for select to authenticated using(sender_id=auth.uid() or receiver_id=auth.uid());
drop policy if exists "send friend requests" on public.friend_requests;
create policy "send friend requests" on public.friend_requests for insert to authenticated with check(sender_id=auth.uid() and status='pending');
drop policy if exists "receiver can update request" on public.friend_requests;
create policy "receiver can update request" on public.friend_requests for update to authenticated using(receiver_id=auth.uid() and status='pending') with check(receiver_id=auth.uid() and status in ('accepted','rejected'));

drop policy if exists "friendships visible to participants" on public.friendships;
create policy "friendships visible to participants" on public.friendships for select to authenticated using(user_low=auth.uid() or user_high=auth.uid());

drop policy if exists "rooms visible to members or public waiting rooms" on public.rooms;
create policy "rooms visible to members or public waiting rooms" on public.rooms for select to authenticated using(is_public and status='waiting' or public.is_scrabble_room_member(id));
-- Room state is changed only through narrowly scoped SECURITY DEFINER RPCs.
-- Clients must not directly update rooms.game_state or other room columns.
drop policy if exists "host updates room" on public.rooms;

drop policy if exists "members see room members" on public.room_members;
create policy "members see room members" on public.room_members for select to authenticated using(public.is_scrabble_room_member(room_id));
drop policy if exists "join own room membership" on public.room_members;
drop policy if exists "users update own membership" on public.room_members;
-- Membership readiness changes only through set_scrabble_ready; withdrawal only through its RPC.
drop policy if exists "users leave own room" on public.room_members;
drop policy if exists "users leave waiting or finished rooms" on public.room_members;
create policy "users leave waiting or finished rooms" on public.room_members for delete to authenticated using(user_id=auth.uid() and exists(select 1 from public.rooms r where r.id=room_id and r.status in ('waiting','finished')));

drop policy if exists "room members read chat" on public.room_messages;
create policy "room members read chat" on public.room_messages for select to authenticated using(public.is_scrabble_room_member(room_id));
drop policy if exists "room members send chat" on public.room_messages;
create policy "room members send chat" on public.room_messages for insert to authenticated with check(sender_id=auth.uid() and public.is_scrabble_room_member(room_id));

drop policy if exists "direct message participants read" on public.direct_messages;
create policy "direct message participants read" on public.direct_messages for select to authenticated using(sender_id=auth.uid() or recipient_id=auth.uid());
drop policy if exists "send direct messages" on public.direct_messages;
create policy "send direct messages" on public.direct_messages for insert to authenticated with check(sender_id=auth.uid() and exists(select 1 from public.friendships f where (f.user_low=auth.uid() and f.user_high=recipient_id) or (f.user_high=auth.uid() and f.user_low=recipient_id)));

drop policy if exists "room invite participants read" on public.room_invites;
create policy "room invite participants read" on public.room_invites for select to authenticated using(sender_id=auth.uid() or receiver_id=auth.uid());
drop policy if exists "send room invites" on public.room_invites;
create policy "send room invites" on public.room_invites for insert to authenticated with check(sender_id=auth.uid() and public.is_scrabble_room_member(room_id));
drop policy if exists "receiver updates room invite" on public.room_invites;
create policy "receiver updates room invite" on public.room_invites for update to authenticated using(receiver_id=auth.uid() and status='pending') with check(receiver_id=auth.uid() and status in ('accepted','rejected'));

grant execute on function public.is_scrabble_room_member(uuid) to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.join_room_by_code(text) to authenticated;
grant execute on function public.create_scrabble_room(text,boolean,int,text) to authenticated;

-- Enable realtime replication for the tables used by the app.
do $$
begin
  alter publication supabase_realtime add table public.room_messages;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.direct_messages;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.room_members;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.rooms;
exception when duplicate_object then null;
end $$;


-- Room readiness and host-controlled start.
create or replace function public.set_scrabble_ready(target_room uuid, ready_state boolean)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_scrabble_room_member(target_room) then raise exception 'Room membership required'; end if;
  update public.room_members set is_ready=ready_state where room_id=target_room and user_id=auth.uid() and not is_withdrawn;
end;
$$;

create or replace function public.start_scrabble_room(target_room uuid)
returns public.rooms language plpgsql security definer set search_path = public
as $$
declare target public.rooms; member_count int; ready_count int;
begin
  select * into target from public.rooms where id=target_room for update;
  if not found then raise exception 'Room not found'; end if;
  if target.host_id <> auth.uid() then raise exception 'Only the host can start the match'; end if;
  if target.status <> 'waiting' then raise exception 'Room has already started'; end if;
  select count(*), count(*) filter (where is_ready or user_id=auth.uid()) into member_count, ready_count from public.room_members where room_id=target_room;
  if member_count < 2 then raise exception 'At least two players are required'; end if;
  if member_count <> ready_count then raise exception 'All players must be ready'; end if;
  update public.rooms set status='playing', game_state=jsonb_build_object('phase','initial_draw','player_ids',(select jsonb_agg(user_id order by seat) from public.room_members where room_id=target_room),'board',jsonb_build_array(),'turn_index',0,'revision',1), updated_at=now() where id=target_room returning * into target;
  return target;
end;
$$;

grant execute on function public.set_scrabble_ready(uuid,boolean) to authenticated;
grant execute on function public.start_scrabble_room(uuid) to authenticated;


-- Premium squares use the fixed standard Scrabble board layout.
-- Remove the former room-specific editor and any saved custom layouts.
drop function if exists public.save_scrabble_room_layout(uuid, jsonb);
alter table public.rooms drop column if exists premium_layout;


-- Private per-player state: never put racks or hidden tiles in rooms.game_state.
-- Players may read only their own private row. Direct writes stay disabled until
-- a trusted server-side turn pipeline validates rack contents and tile ownership.
create table if not exists public.room_player_private (
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  private_state jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key(room_id,user_id)
);

alter table public.room_player_private enable row level security;
drop policy if exists "players read only their private room state" on public.room_player_private;
create policy "players read only their private room state"
  on public.room_player_private for select to authenticated
  using(user_id=auth.uid() and public.is_scrabble_room_member(room_id));
drop policy if exists "players insert only their private room state" on public.room_player_private;
drop policy if exists "players update only their private room state" on public.room_player_private;
revoke all on public.room_player_private from anon, authenticated;
grant select on public.room_player_private to authenticated;

-- The private table must exist before it is added to the realtime publication.
do $$
begin
  alter publication supabase_realtime add table public.room_player_private;
exception when duplicate_object then null;
end $$;

-- Atomically publish the visible match state and save only the caller's private rack.
-- The client must omit all hidden tile data from public_state.
create or replace function public.submit_scrabble_turn(
  target_room uuid,
  expected_revision integer,
  public_state jsonb,
  private_state jsonb
)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.rooms;
  player_ids jsonb;
  turn_index integer;
  next_state jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if jsonb_typeof(public_state) <> 'object' or jsonb_typeof(private_state) <> 'object' then
    raise exception 'Invalid game state';
  end if;
  -- Accept only the visible fields used by the match screen.
  if exists (
    select 1 from jsonb_object_keys(public_state) as fields(field_name)
    where field_name not in ('phase','board','scores','turn_index','log','remaining_tiles','consecutive_passes','finished')
  ) then
    raise exception 'Unsupported public game-state field';
  end if;
  if jsonb_typeof(public_state->'board') is distinct from 'array'
     or jsonb_typeof(public_state->'scores') is distinct from 'object'
     or jsonb_typeof(private_state->'rack') is distinct from 'array'
     or jsonb_array_length(private_state->'rack') > 7 then
    raise exception 'Invalid board, score, or private rack data';
  end if;

  select * into target from public.rooms where id=target_room for update;
  if not found or target.status <> 'playing' then raise exception 'Match is not active'; end if;
  if not public.is_scrabble_room_member(target_room) then raise exception 'Room membership required'; end if;
  if coalesce((target.game_state->>'revision')::integer,0) <> expected_revision then
    raise exception 'Game state changed; refresh and try again';
  end if;

  player_ids := target.game_state->'player_ids';
  turn_index := coalesce((target.game_state->>'turn_index')::integer,0);
  if jsonb_typeof(player_ids) <> 'array' or jsonb_array_length(player_ids)=0 then
    raise exception 'Match player order is missing';
  end if;
  if turn_index < 0 or turn_index >= jsonb_array_length(player_ids)
     or player_ids->>turn_index <> auth.uid()::text then
    raise exception 'It is not your turn';
  end if;
  if coalesce((public_state->>'turn_index')::integer,-1)
     <> mod(turn_index + 1, jsonb_array_length(player_ids)) then
    raise exception 'Turn must pass to the next player';
  end if;

  next_state := public_state
    || jsonb_build_object(
      'player_ids', player_ids,
      'revision', expected_revision + 1
    );

  update public.rooms
    set game_state=next_state, updated_at=now()
    where id=target_room
    returning * into target;

  insert into public.room_player_private(room_id,user_id,private_state,updated_at)
    values(target_room,auth.uid(),private_state,now())
  on conflict(room_id,user_id) do update
    set private_state=excluded.private_state, updated_at=now();

  return target;
end;
$$;

-- Keep turn submission disabled until server-side tile-bag, rack ownership,
-- move validation, dictionary validation, and score calculation are implemented.
revoke execute on function public.submit_scrabble_turn(uuid,integer,jsonb,jsonb) from public, anon, authenticated;


-- Host can finish an active match. Scores are revealed by the client only
-- after the room status changes to finished.
create or replace function public.finish_scrabble_room(target_room uuid)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare target public.rooms;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into target from public.rooms where id=target_room for update;
  if not found then raise exception 'Room not found'; end if;
  if target.host_id <> auth.uid() then raise exception 'Only the host can finish the match'; end if;
  if target.status <> 'playing' then raise exception 'Match is not active'; end if;
  update public.rooms
    set status='finished',
        game_state=coalesce(game_state,'{}'::jsonb)
          || jsonb_build_object('finished',true,'finish_reason','host'),
        updated_at=now()
    where id=target_room
    returning * into target;
  return target;
end;
$$;
grant execute on function public.finish_scrabble_room(uuid) to authenticated;


-- A player may withdraw from an active room without ending the match.
alter table public.room_members
  add column if not exists is_withdrawn boolean not null default false;

create or replace function public.withdraw_scrabble_room(target_room uuid)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare target public.rooms;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into target from public.rooms where id=target_room for update;
  if not found then raise exception 'Room not found'; end if;
  if target.status <> 'playing' then raise exception 'Match is not active'; end if;
  if not exists (
    select 1 from public.room_members
    where room_id=target_room and user_id=auth.uid()
  ) then raise exception 'Room membership required'; end if;
  update public.room_members
    set is_withdrawn=true, is_ready=false
    where room_id=target_room and user_id=auth.uid();
  return target;
end;
$$;
revoke all on function public.withdraw_scrabble_room(uuid) from public, anon;
grant execute on function public.withdraw_scrabble_room(uuid) to authenticated;


-- Server-owned tile bag. No client role receives table privileges or an RLS policy.
create table if not exists public.room_tile_bag (
  room_id uuid not null references public.rooms(id) on delete cascade,
  position integer not null,
  tile jsonb not null,
  primary key(room_id,position)
);
alter table public.room_tile_bag enable row level security;
revoke all on public.room_tile_bag from public, anon, authenticated;

-- Compare starting tiles on the server: closest to A/alif starts; ties redraw.
create or replace function public.scrabble_start_rank(p_letter text, p_language text)
returns integer
language sql
immutable
set search_path = public
as $$
  select case
    when p_letter = '★' then 10000
    when p_language = 'en' then
      case when upper(p_letter) between 'A' and 'Z'
        then ascii(upper(p_letter)) - ascii('A')
        else 10000 end
    when p_language = 'ar' then
      case
        when p_letter in ('ا','أ','إ','آ','ء','ؤ','ئ','ئ أول الكلمة') then 0
        when p_letter in ('لا','لأ','لإ','لآ') then 22
        when p_letter = 'ة' then 25
        when p_letter in ('ى','يء') then 27
        else case when strpos('ابتثجحخدذرزسشصضطظعغفقكلمنهوي',p_letter)>0 then strpos('ابتثجحخدذرزسشصضطظعغفقكلمنهوي',p_letter)-1 else 10000 end
      end
    else 10000
  end;
$$;
revoke all on function public.scrabble_start_rank(text,text) from public, anon, authenticated;

-- Deal private racks, resolve the first player, and publish the initial match atomically.
create or replace function public.start_scrabble_room(target_room uuid)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.rooms;
  member_count integer;
  ready_count integer;
  player record;
  draw_row record;
  rack_json jsonb;
  start_json jsonb;
  players_json jsonb;
  scores_json jsonb;
  dealt_count integer;
  eligible_seats integer[];
  tied_seats integer[];
  seat_index integer;
  best_rank integer;
  current_rank integer;
  round_no integer;
  chosen_seat integer;
  winner_index integer;
  returned_position integer;
  draws_this_round jsonb;
  all_draws jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into target from public.rooms where id=target_room for update;
  if not found then raise exception 'Room not found'; end if;
  if target.host_id <> auth.uid() then raise exception 'Only the host can start the match'; end if;
  if target.status <> 'waiting' then raise exception 'Room has already started'; end if;

  select count(*), count(*) filter (where is_ready or user_id=auth.uid())
    into member_count, ready_count
    from public.room_members where room_id=target_room and not is_withdrawn;
  if member_count < 2 then raise exception 'At least two players are required'; end if;
  if member_count <> ready_count then raise exception 'All players must be ready'; end if;

  delete from public.room_tile_bag where room_id=target_room;
  delete from public.room_player_private where room_id=target_room;

  if target.language='en' then
    insert into public.room_tile_bag(room_id,position,tile)
    select target_room, row_number() over(order by random())::integer,
      jsonb_build_object('id',gen_random_uuid(),'letter',v.letter,'points',v.points,'isBlank',v.letter='★')
    from (values
      ('A',1,9),('B',3,2),('C',3,2),('D',2,4),('E',1,12),('F',4,2),
      ('G',2,3),('H',4,2),('I',1,9),('J',8,1),('K',5,1),('L',1,4),
      ('M',3,2),('N',1,6),('O',1,8),('P',3,2),('Q',10,1),('R',1,6),
      ('S',1,4),('T',1,6),('U',1,4),('V',4,2),('W',4,2),('X',8,1),
      ('Y',4,2),('Z',10,1),('★',0,2)
    ) as v(letter,points,quantity)
    cross join lateral generate_series(1,v.quantity);
  elsif target.language='ar' then
    insert into public.room_tile_bag(room_id,position,tile)
    select target_room, row_number() over(order by random())::integer,
      jsonb_build_object('id',gen_random_uuid(),'letter',v.letter,'points',v.points,'isBlank',v.letter='★')
    from (values
      ('ا',1,8),('إ',1,2),('أ',1,2),('آ',8,1),('ب',1,4),('ج',1,3),
      ('ح',1,3),('خ',1,3),('د',1,3),('ذ',1,3),('ش',2,3),('ص',2,3),
      ('ض',3,3),('ط',2,2),('ظ',4,2),('ق',2,3),('ك',3,3),('ل',1,3),
      ('لا',2,2),('لإ',3,1),('ن',1,3),('ه',1,3),('و',1,3),('ؤ',10,1),
      ('ي',1,3),('ء',8,1),('ئ أول الكلمة',10,2),('★',0,2),('ت',1,4),
      ('ة',5,1),('ث',1,3),('ر',1,3),('ز',2,3),('س',1,3),('ع',2,3),
      ('غ',4,3),('ف',1,3),('لأ',3,1),('لآ',3,1),('م',1,4),('يء',5,1),
      ('ى',3,1),('ئ',8,1)
    ) as v(letter,points,quantity)
    cross join lateral generate_series(1,v.quantity);
  else
    raise exception 'Unsupported room language';
  end if;

  select jsonb_agg(user_id order by seat),
         jsonb_object_agg(user_id::text,0)
    into players_json,scores_json
    from public.room_members where room_id=target_room and not is_withdrawn;

  -- Each active player receives one comparison tile and seven private rack tiles.
  for player in
    select user_id,seat,row_number() over(order by seat)::integer as deal_index from public.room_members
    where room_id=target_room and not is_withdrawn order by seat
  loop
    select tile into start_json from public.room_tile_bag
      where room_id=target_room and position=player.deal_index;
    select coalesce(jsonb_agg(tile order by position),'[]'::jsonb) into rack_json
      from public.room_tile_bag
      where room_id=target_room
        and position between member_count+(player.deal_index-1)*7+1
                          and member_count+player.deal_index*7;
    if start_json is null or jsonb_array_length(rack_json)<>7 then
      raise exception 'Not enough tiles to initialize every player';
    end if;
    insert into public.room_player_private(room_id,user_id,private_state)
      values(target_room,player.user_id,jsonb_build_object('rack',rack_json,'starting_draw',start_json));
  end loop;

  dealt_count := member_count*8;
  delete from public.room_tile_bag where room_id=target_room and position<=dealt_count;

  select array_agg(seat order by seat) into eligible_seats
    from public.room_members where room_id=target_room and not is_withdrawn;

  -- Redraw only tied players. Every comparison tile is returned to the bag afterward.
  for round_no in 1..100 loop
    best_rank := 2147483647;
    tied_seats := array[]::integer[];
    draws_this_round := '[]'::jsonb;

    foreach seat_index in array eligible_seats loop
      select m.user_id, p.private_state->'starting_draw' as tile
        into draw_row
        from public.room_members m
        join public.room_player_private p
          on p.room_id=m.room_id and p.user_id=m.user_id
        where m.room_id=target_room and m.seat=seat_index;
      current_rank := public.scrabble_start_rank(draw_row.tile->>'letter',target.language);
      draws_this_round := draws_this_round || jsonb_build_array(
        jsonb_build_object('user_id',draw_row.user_id,'letter',draw_row.tile->>'letter')
      );
      if current_rank < best_rank then
        best_rank := current_rank;
        tied_seats := array[seat_index];
      elsif current_rank = best_rank then
        tied_seats := array_append(tied_seats,seat_index);
      end if;
    end loop;

    all_draws := all_draws || jsonb_build_array(
      jsonb_build_object('round',round_no,'draws',draws_this_round)
    );

    if cardinality(tied_seats)=1 then
      chosen_seat := tied_seats[1];
      exit;
    end if;

    if (select count(*) from public.room_tile_bag where room_id=target_room) < cardinality(tied_seats) then
      raise exception 'Not enough tiles to resolve a starting-draw tie';
    end if;

    for draw_row in
      select m.user_id, p.private_state->'starting_draw' as tile
      from public.room_members m
      join public.room_player_private p on p.room_id=m.room_id and p.user_id=m.user_id
      where m.room_id=target_room and m.seat=any(tied_seats)
    loop
      select coalesce(max(position),0)+1 into returned_position
        from public.room_tile_bag where room_id=target_room;
      insert into public.room_tile_bag(room_id,position,tile)
        values(target_room,returned_position,draw_row.tile);
    end loop;

    foreach seat_index in array tied_seats loop
      select position,tile into draw_row
        from public.room_tile_bag
        where room_id=target_room
        order by random()
        limit 1
        for update;
      if not found then raise exception 'Not enough tiles for tie-break'; end if;
      delete from public.room_tile_bag
        where room_id=target_room and position=draw_row.position;
      update public.room_player_private p
        set private_state=jsonb_set(p.private_state,'{starting_draw}',draw_row.tile,true),
            updated_at=now()
        from public.room_members m
        where p.room_id=target_room and p.user_id=m.user_id
          and m.room_id=target_room and m.seat=seat_index;
    end loop;

    eligible_seats := tied_seats;
  end loop;

  if chosen_seat is null then raise exception 'Starting-draw tie-break did not resolve'; end if;

  -- Return the final comparison tiles; they are not part of any player's rack.
  for draw_row in
    select private_state->'starting_draw' as tile
    from public.room_player_private where room_id=target_room
  loop
    select coalesce(max(position),0)+1 into returned_position
      from public.room_tile_bag where room_id=target_room;
    insert into public.room_tile_bag(room_id,position,tile)
      values(target_room,returned_position,draw_row.tile);
  end loop;

  select array_position(array_agg(user_id order by seat),
      (select user_id from public.room_members where room_id=target_room and seat=chosen_seat))-1
    into winner_index
    from public.room_members where room_id=target_room and not is_withdrawn;

  update public.rooms
    set status='playing',
        game_state=jsonb_build_object(
          'phase','playing',
          'player_ids',players_json,
          'board',jsonb_build_array(),
          'scores',scores_json,
          'turn_index',winner_index,
          'starter_user_id',(select user_id from public.room_members where room_id=target_room and seat=chosen_seat),
          'starting_draws',all_draws,
          'remaining_tiles',(select count(*) from public.room_tile_bag where room_id=target_room),
          'revision',1
        ),
        updated_at=now()
    where id=target_room returning * into target;
  return target;
end;
$$;
grant execute on function public.start_scrabble_room(uuid) to authenticated;
 

-- Exchange tiles only through the trusted server; rack and bag never reach client writes.
create or replace function public.exchange_scrabble_tiles(
  target_room uuid,
  expected_revision integer,
  tile_ids uuid[]
)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $exchange$
declare
  target public.rooms;
  private_row public.room_player_private;
  rack_json jsonb;
  kept_rack jsonb;
  drawn_tiles jsonb := '[]'::jsonb;
  new_rack jsonb;
  selected_tile jsonb;
  selected_count integer;
  unique_count integer;
  bag_count integer;
  player_ids jsonb;
  player_count integer;
  current_index integer;
  next_index integer := -1;
  next_user uuid;
  step integer;
  pass_count integer;
  next_log jsonb;
  bag_position integer;
  bag_row record;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if tile_ids is null or cardinality(tile_ids) < 1 or cardinality(tile_ids) > 7 then
    raise exception 'Choose between 1 and 7 tiles';
  end if;
  selected_count := cardinality(tile_ids);
  select count(distinct selected_id) into unique_count
    from unnest(tile_ids) as selected(selected_id);
  if unique_count <> selected_count then raise exception 'Duplicate tile selection'; end if;

  select * into target from public.rooms where id=target_room for update;
  if not found or target.status <> 'playing' then raise exception 'Match is not active'; end if;
  if not public.is_scrabble_room_member(target_room) then raise exception 'Room membership required'; end if;
  if exists(select 1 from public.room_members where room_id=target_room and user_id=auth.uid() and is_withdrawn) then
    raise exception 'Withdrawn players cannot take turns';
  end if;
  if coalesce((target.game_state->>'revision')::integer,0) <> expected_revision then
    raise exception 'Game state changed; refresh and try again';
  end if;

  player_ids := target.game_state->'player_ids';
  player_count := coalesce(jsonb_array_length(player_ids),0);
  current_index := coalesce((target.game_state->>'turn_index')::integer,-1);
  if player_count < 2 or current_index < 0 or current_index >= player_count
     or player_ids->>current_index <> auth.uid()::text then
    raise exception 'It is not your turn';
  end if;

  select * into private_row from public.room_player_private
    where room_id=target_room and user_id=auth.uid() for update;
  if not found then raise exception 'Your private rack was not found'; end if;
  rack_json := private_row.private_state->'rack';
  if jsonb_typeof(rack_json) is distinct from 'array' then raise exception 'Your rack is invalid'; end if;
  if exists(
    select 1 from unnest(tile_ids) as chosen(id)
    where not exists(
      select 1 from jsonb_array_elements(rack_json) as rack(rack_tile)
      where rack.rack_tile->>'id'=chosen.id::text
    )
  ) then raise exception 'A selected tile is not in your rack'; end if;

  select count(*) into bag_count from public.room_tile_bag where room_id=target_room;
  if bag_count < 7 or bag_count < selected_count then raise exception 'At least seven tiles must remain in the bag to exchange'; end if;

  for bag_row in
    select position,tile from public.room_tile_bag
    where room_id=target_room order by position limit selected_count for update
  loop
    drawn_tiles := drawn_tiles || jsonb_build_array(bag_row.tile);
    delete from public.room_tile_bag where room_id=target_room and position=bag_row.position;
  end loop;
  if jsonb_array_length(drawn_tiles) <> selected_count then raise exception 'Could not draw replacement tiles'; end if;

  select coalesce(jsonb_agg(rack_tile order by ordinal), '[]'::jsonb)
    into kept_rack
    from jsonb_array_elements(rack_json) with ordinality as rack(rack_tile,ordinal)
    where not ((rack_tile->>'id') = any(array(select unnest(tile_ids)::text)));
  new_rack := kept_rack || drawn_tiles;

  select coalesce(max(position),0) into bag_position
    from public.room_tile_bag where room_id=target_room;
  for selected_tile in
    select rack_tile
    from jsonb_array_elements(rack_json) with ordinality as rack(rack_tile,ordinal)
    where (rack_tile->>'id') = any(array(select unnest(tile_ids)::text))
    order by ordinal
  loop
    bag_position := bag_position+1;
    insert into public.room_tile_bag(room_id,position,tile)
      values(target_room,bag_position,selected_tile);
  end loop;

  -- Return exchanged tiles to the bag, then shuffle the whole remaining bag.
  update public.room_tile_bag
    set position=position+bag_position+1000
    where room_id=target_room;
  with randomized as (
    select position,row_number() over(order by random())::integer as new_position
    from public.room_tile_bag where room_id=target_room
  )
  update public.room_tile_bag b
    set position=randomized.new_position
    from randomized
    where b.room_id=target_room and b.position=randomized.position;

  update public.room_player_private
    set private_state=private_row.private_state || jsonb_build_object('rack',new_rack),
        updated_at=now()
    where room_id=target_room and user_id=auth.uid();

  for step in 1..player_count loop
    next_index := mod(current_index+step,player_count);
    next_user := (player_ids->>next_index)::uuid;
    if exists(select 1 from public.room_members where room_id=target_room and user_id=next_user and not is_withdrawn) then
      exit;
    end if;
    next_user := null;
  end loop;
  if next_user is null then raise exception 'No active players remain'; end if;

  pass_count := coalesce((target.game_state->>'consecutive_passes')::integer,0)+1;
  next_log := coalesce(target.game_state->'log','[]'::jsonb)
    || jsonb_build_array(jsonb_build_object('type','exchange','user_id',auth.uid(),'count',selected_count,'at',now()));

  update public.rooms
    set game_state=target.game_state || jsonb_build_object(
      'turn_index',next_index,
      'consecutive_passes',pass_count,
      'remaining_tiles',(select count(*) from public.room_tile_bag where room_id=target_room),
      'log',next_log,
      'revision',expected_revision+1
    ),
    updated_at=now()
    where id=target_room returning * into target;
  return target;
end;
$exchange$;
revoke all on function public.exchange_scrabble_tiles(uuid,integer,uuid[]) from public, anon;
grant execute on function public.exchange_scrabble_tiles(uuid,integer,uuid[]) to authenticated;


-- A pass is a server-authoritative action: it never accepts client board,
-- score, rack, or tile-bag data.
create or replace function public.pass_scrabble_turn(
  target_room uuid,
  expected_revision integer
)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.rooms;
  player_ids jsonb;
  current_index integer;
  next_index integer;
  player_count integer;
  step integer;
  next_user uuid;
  pass_count integer;
  next_log jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;

  select * into target
  from public.rooms
  where id=target_room
  for update;

  if not found or target.status <> 'playing' then
    raise exception 'Match is not active';
  end if;
  if not public.is_scrabble_room_member(target_room) then
    raise exception 'Room membership required';
  end if;
  if exists(
    select 1 from public.room_members
    where room_id=target_room and user_id=auth.uid() and is_withdrawn
  ) then
    raise exception 'Withdrawn players cannot take turns';
  end if;

  if coalesce((target.game_state->>'revision')::integer,0) <> expected_revision then
    raise exception 'Game state changed; refresh and try again';
  end if;

  player_ids := target.game_state->'player_ids';
  player_count := coalesce(jsonb_array_length(player_ids),0);
  current_index := coalesce((target.game_state->>'turn_index')::integer,-1);

  if player_count < 2 or current_index < 0 or current_index >= player_count then
    raise exception 'Match player order is invalid';
  end if;
  if player_ids->>current_index <> auth.uid()::text then
    raise exception 'It is not your turn';
  end if;

  next_index := -1;
  next_user := null;
  for step in 1..player_count loop
    next_index := mod(current_index + step, player_count);
    next_user := (player_ids->>next_index)::uuid;
    if exists(
      select 1 from public.room_members
      where room_id=target_room and user_id=next_user and not is_withdrawn
    ) then
      exit;
    end if;
    next_user := null;
  end loop;
  if next_user is null then
    raise exception 'No active players remain';
  end if;

  pass_count := coalesce((target.game_state->>'consecutive_passes')::integer,0)+1;
  next_log := coalesce(target.game_state->'log','[]'::jsonb)
    || jsonb_build_array(jsonb_build_object(
      'type','pass',
      'user_id',auth.uid(),
      'at',now()
    ));

  update public.rooms
  set game_state=target.game_state || jsonb_build_object(
        'turn_index',next_index,
        'consecutive_passes',pass_count,
        'log',next_log,
        'revision',expected_revision+1
      ),
      updated_at=now()
  where id=target_room
  returning * into target;

  return target;
end;
$$;

revoke all on function public.pass_scrabble_turn(uuid,integer) from public, anon;
grant execute on function public.pass_scrabble_turn(uuid,integer) to authenticated;


-- Security hardening and lookup indexes.
-- room_tile_bag intentionally has RLS enabled with no client policies:
-- only SECURITY DEFINER room RPCs may access the server-owned tile bag.
revoke all on function public.accept_friend_request(uuid) from public, anon;
grant execute on function public.accept_friend_request(uuid) to authenticated;
revoke all on function public.create_profile_for_new_user() from public, anon, authenticated;
revoke all on function public.create_scrabble_room(text, boolean, integer, text) from public, anon;
grant execute on function public.create_scrabble_room(text, boolean, integer, text) to authenticated;
revoke all on function public.finish_scrabble_room(uuid) from public, anon;
grant execute on function public.finish_scrabble_room(uuid) to authenticated;
revoke all on function public.is_scrabble_room_member(uuid) from public, anon;
grant execute on function public.is_scrabble_room_member(uuid) to authenticated;
revoke all on function public.join_room_by_code(text) from public, anon;
grant execute on function public.join_room_by_code(text) to authenticated;
revoke all on function public.set_scrabble_ready(uuid, boolean) from public, anon;
grant execute on function public.set_scrabble_ready(uuid, boolean) to authenticated;
revoke all on function public.start_scrabble_room(uuid) from public, anon;
grant execute on function public.start_scrabble_room(uuid) to authenticated;

create index if not exists direct_messages_recipient_id_idx on public.direct_messages(recipient_id);
create index if not exists direct_messages_sender_id_idx on public.direct_messages(sender_id);
create index if not exists friend_requests_receiver_id_idx on public.friend_requests(receiver_id);
create index if not exists friendships_user_high_id_idx on public.friendships(user_high);
create index if not exists room_invites_receiver_id_idx on public.room_invites(receiver_id);
create index if not exists room_invites_room_id_idx on public.room_invites(room_id);
create index if not exists room_invites_sender_id_idx on public.room_invites(sender_id);
create index if not exists room_members_user_id_idx on public.room_members(user_id);
create index if not exists room_messages_room_id_idx on public.room_messages(room_id);
create index if not exists room_messages_sender_id_idx on public.room_messages(sender_id);
create index if not exists room_player_private_user_id_idx on public.room_player_private(user_id);
create index if not exists rooms_host_id_idx on public.rooms(host_id);


-- Server-authoritative word placement. Execute privilege is limited to service_role;
-- the scrabble-move Edge Function authenticates the user and validates dictionary entries.
CREATE OR REPLACE FUNCTION public.place_scrabble_word(target_room uuid, expected_revision integer, placements jsonb, validated_words jsonb, actor uuid)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target public.rooms;
  private_row public.room_player_private;
  rack jsonb;
  board jsonb;
  candidate_board jsonb;
  placement jsonb;
  tile jsonb;
  cell_tile jsonb;
  p record;
  r integer;
  c integer;
  idx integer;
  min_axis integer;
  max_axis integer;
  fixed_axis integer;
  horizontal boolean;
  first_move boolean;
  connected boolean := false;
  new_positions integer[] := array[]::integer[];
  used_ids text[] := array[]::text[];
  computed_keys text[] := array[]::text[];
  computed_words text[] := array[]::text[];
  validated_array text[] := array[]::text[];
  words_json jsonb := '[]'::jsonb;
  rack_kept jsonb;
  rack_next jsonb;
  drawn jsonb := '[]'::jsonb;
  bag_row record;
  draw_count integer;
  axis integer;
  start_idx integer;
  cursor_idx integer;
  word_text text;
  word_len integer;
  subtotal integer;
  word_multiplier integer;
  tile_points integer;
  premium text;
  word_points integer;
  total_points integer := 0;
  bingo integer := 0;
  scores jsonb;
  player_ids jsonb;
  player_count integer;
  current_index integer;
  next_index integer := -1;
  next_user uuid;
  step integer;
  next_log jsonb;
  key_text text;
  i integer;
begin
  if actor is null then raise exception 'Sign in required'; end if;
  if jsonb_typeof(placements) is distinct from 'array'
     or jsonb_array_length(placements) < 1
     or jsonb_array_length(placements) > 7 then
    raise exception 'Place between 1 and 7 tiles';
  end if;
  if jsonb_typeof(validated_words) is distinct from 'array' then
    raise exception 'Invalid dictionary result';
  end if;

  select * into target from public.rooms where id=target_room for update;
  if not found or target.status <> 'playing' then raise exception 'Match is not active'; end if;
  if not exists(select 1 from public.room_members where room_id=target_room and user_id=actor and not is_withdrawn) then
    raise exception 'Active room membership required';
  end if;
  if coalesce((target.game_state->>'revision')::integer,0) <> expected_revision then
    raise exception 'Game state changed; refresh and try again';
  end if;

  player_ids := target.game_state->'player_ids';
  player_count := coalesce(jsonb_array_length(player_ids),0);
  current_index := coalesce((target.game_state->>'turn_index')::integer,-1);
  if player_count < 2 or current_index < 0 or current_index >= player_count
     or player_ids->>current_index <> actor::text then
    raise exception 'It is not your turn';
  end if;

  select * into private_row
  from public.room_player_private
  where room_id=target_room and user_id=actor
  for update;
  if not found then raise exception 'Your private rack was not found'; end if;
  rack := private_row.private_state->'rack';
  if jsonb_typeof(rack) is distinct from 'array' then raise exception 'Your rack is invalid'; end if;

  board := target.game_state->'board';
  if board is null or jsonb_typeof(board) is distinct from 'array' then
    raise exception 'The match board is invalid';
  end if;
  if jsonb_array_length(board)=0 then
    select jsonb_agg('null'::jsonb order by n) into board from generate_series(0,224) n;
  elsif jsonb_array_length(board)<>225 then
    raise exception 'The match board has an invalid size';
  end if;
  candidate_board := board;

  for p in select value from jsonb_array_elements(placements)
  loop
    if jsonb_typeof(p.value) is distinct from 'object'
       or coalesce((p.value->>'row')::integer,-1) not between 0 and 14
       or coalesce((p.value->>'col')::integer,-1) not between 0 and 14
       or nullif(p.value->>'tileId','') is null then
      raise exception 'Invalid tile placement';
    end if;
    r := (p.value->>'row')::integer;
    c := (p.value->>'col')::integer;
    idx := r*15+c;
    if idx = any(new_positions) then raise exception 'Two tiles cannot occupy the same square'; end if;
    if candidate_board->idx <> 'null'::jsonb then raise exception 'That square is already occupied'; end if;
    if (p.value->>'tileId') = any(used_ids) then raise exception 'A tile cannot be used twice'; end if;

    select value into tile
    from jsonb_array_elements(rack)
    where value->>'id'=p.value->>'tileId';
    if tile is null then raise exception 'A selected tile is not in your rack'; end if;

    if coalesce((tile->>'isBlank')::boolean,false) then
      if nullif(trim(p.value->>'blankAs'),'') is null or length(p.value->>'blankAs')>8 then
        raise exception 'Choose the letter represented by the blank tile';
      end if;
      tile := jsonb_set(tile,'{blankAs}',to_jsonb(trim(p.value->>'blankAs')),true);
      tile := jsonb_set(tile,'{points}','0'::jsonb,true);
    else
      tile := tile - 'blankAs';
    end if;

    candidate_board := jsonb_set(candidate_board,array[idx::text],tile,true);
    new_positions := array_append(new_positions,idx);
    used_ids := array_append(used_ids,p.value->>'tileId');
  end loop;

  first_move := not exists(
    select 1 from jsonb_array_elements(board) as cell(value)
    where cell.value <> 'null'::jsonb
  );

  horizontal := (select count(distinct (value->>'row'))=1 from jsonb_array_elements(placements));
  if not horizontal and (select count(distinct (value->>'col'))<>1 from jsonb_array_elements(placements)) then
    raise exception 'Tiles must be placed in one straight line';
  end if;

  if horizontal then
    select min((value->>'col')::integer),max((value->>'col')::integer),min((value->>'row')::integer)
    into min_axis,max_axis,fixed_axis from jsonb_array_elements(placements);
  else
    select min((value->>'row')::integer),max((value->>'row')::integer),min((value->>'col')::integer)
    into min_axis,max_axis,fixed_axis from jsonb_array_elements(placements);
  end if;

  for axis in min_axis..max_axis loop
    idx := case when horizontal then fixed_axis*15+axis else axis*15+fixed_axis end;
    if candidate_board->idx = 'null'::jsonb then raise exception 'There cannot be a gap between placed tiles'; end if;
  end loop;

  if first_move then
    if candidate_board->112='null'::jsonb then raise exception 'The first word must cover the center square'; end if;
  else
    foreach idx in array new_positions loop
      if (idx>=15 and board->(idx-15)<>'null'::jsonb)
         or (idx<210 and board->(idx+15)<>'null'::jsonb)
         or (idx%15>0 and board->(idx-1)<>'null'::jsonb)
         or (idx%15<14 and board->(idx+1)<>'null'::jsonb) then
        connected := true;
      end if;
    end loop;
    if not connected then raise exception 'Your word must connect to an existing tile'; end if;
  end if;

  -- Reconstruct every main/cross word from the authoritative board.
  for i in 1..2 loop
    foreach idx in array new_positions loop
      if i=1 then
        axis := 1; -- horizontal
      else
        axis := 15; -- vertical
      end if;
      start_idx := idx;
      while start_idx-axis>=0 and start_idx-axis<225 loop
        if (axis=1 and start_idx/15<>(start_idx-axis)/15) then exit; end if;
        if candidate_board->(start_idx-axis)='null'::jsonb then exit; end if;
        start_idx := start_idx-axis;
      end loop;
      cursor_idx := start_idx;
      word_text := '';
      word_len := 0;
      subtotal := 0;
      word_multiplier := 1;
      key_text := i::text||':'||start_idx::text;
      while cursor_idx>=0 and cursor_idx<225 loop
        if (axis=1 and cursor_idx/15<>start_idx/15) then exit; end if;
        cell_tile := candidate_board->cursor_idx;
        if cell_tile='null'::jsonb then exit; end if;
        word_text := word_text || coalesce(cell_tile->>'blankAs',cell_tile->>'letter','');
        word_len := word_len+1;
        tile_points := coalesce((cell_tile->>'points')::integer,0);
        if cursor_idx=any(new_positions) then
          premium := case
            when cursor_idx in (0,7,14,105,119,210,217,224) then 'TW'
            when cursor_idx in (18,26,32,42,46,58,64,70,112,154,160,166,178,182,192,198,206) then 'DW'
            when cursor_idx in (20,24,76,80,84,88,136,140,144,148,200,204) then 'TL'
            when cursor_idx in (3,11,36,38,45,52,59,92,96,98,102,108,116,122,126,128,132,165,172,179,186,188,213,221) then 'DL'
            else null end;
          if premium='DL' then tile_points:=tile_points*2; end if;
          if premium='TL' then tile_points:=tile_points*3; end if;
          if premium='DW' then word_multiplier:=word_multiplier*2; end if;
          if premium='TW' then word_multiplier:=word_multiplier*3; end if;
        end if;
        subtotal:=subtotal+tile_points;
        cursor_idx:=cursor_idx+axis;
      end loop;
      if word_len>1 and not (key_text=any(computed_keys)) then
        computed_keys:=array_append(computed_keys,key_text);
        computed_words:=array_append(computed_words,word_text);
        word_points:=subtotal*word_multiplier;
        total_points:=total_points+word_points;
        words_json:=words_json||jsonb_build_array(jsonb_build_object('word',word_text,'points',word_points,'start',start_idx,'direction',case when i=1 then 'horizontal' else 'vertical' end));
      end if;
    end loop;
  end loop;

  if cardinality(computed_words)=0 then raise exception 'The move must create at least one word'; end if;
  select coalesce(array_agg(distinct value order by value),array[]::text[])
  into validated_array from jsonb_array_elements_text(validated_words);
  if (select array_agg(distinct w order by w) from unnest(computed_words) w)
     is distinct from validated_array then
    raise exception 'Dictionary validation did not match the words on the board';
  end if;

  if cardinality(new_positions)=7 then bingo:=50; end if;
  total_points:=total_points+bingo;
  scores:=coalesce(target.game_state->'scores','{}'::jsonb);
  scores:=jsonb_set(scores,array[actor::text],to_jsonb(coalesce((scores->>actor::text)::integer,0)+total_points),true);

  select coalesce(jsonb_agg(value order by ordinality),'[]'::jsonb)
  into rack_kept
  from jsonb_array_elements(rack) with ordinality
  where not ((value->>'id')=any(used_ids));

  draw_count:=cardinality(new_positions);
  for bag_row in
    select position,tile from public.room_tile_bag
    where room_id=target_room order by position limit draw_count for update
  loop
    drawn:=drawn||jsonb_build_array(bag_row.tile);
    delete from public.room_tile_bag where room_id=target_room and position=bag_row.position;
  end loop;
  rack_next:=rack_kept||drawn;

  update public.room_player_private
  set private_state=jsonb_set(private_state,'{rack}',rack_next,true),updated_at=now()
  where room_id=target_room and user_id=actor;

  current_index:=coalesce((target.game_state->>'turn_index')::integer,0);
  next_user:=null;
  for step in 1..player_count loop
    next_index:=mod(current_index+step,player_count);
    next_user:=(player_ids->>next_index)::uuid;
    if exists(select 1 from public.room_members where room_id=target_room and user_id=next_user and not is_withdrawn) then exit; end if;
    next_user:=null;
  end loop;
  if next_user is null then raise exception 'No active players remain'; end if;

  next_log:=coalesce(target.game_state->'log','[]'::jsonb)||jsonb_build_array(
    jsonb_build_object('type','word','user_id',actor,'words',words_json,'points',total_points,'at',now())
  );

  update public.rooms
  set game_state=target.game_state||jsonb_build_object(
    'board',candidate_board,
    'scores',scores,
    'turn_index',next_index,
    'consecutive_passes',0,
    'remaining_tiles',(select count(*) from public.room_tile_bag where room_id=target_room),
    'log',next_log,
    'revision',expected_revision+1
  ),updated_at=now()
  where id=target_room returning * into target;
  return target;
end;
$function$
;
revoke all on function public.place_scrabble_word(uuid,integer,jsonb,jsonb,uuid) from public, anon, authenticated;
grant execute on function public.place_scrabble_word(uuid,integer,jsonb,jsonb,uuid) to service_role;


-- Endgame rack penalties and automatic settlement.
CREATE OR REPLACE FUNCTION public.settle_scrabble_room(target_room uuid, finisher uuid, end_reason text)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target public.rooms;
  scores jsonb;
  player record;
  penalty integer;
  finisher_bonus integer := 0;
  next_log jsonb;
begin
  select * into target
  from public.rooms
  where id=target_room
  for update;
  if not found or target.status <> 'playing' then
    raise exception 'Match is not active';
  end if;

  scores := coalesce(target.game_state->'scores','{}'::jsonb);

  for player in
    select m.user_id, coalesce(p.private_state->'rack','[]'::jsonb) as rack
    from public.room_members m
    left join public.room_player_private p
      on p.room_id=m.room_id and p.user_id=m.user_id
    where m.room_id=target_room and not m.is_withdrawn
    order by m.seat
  loop
    select coalesce(sum(coalesce((tile->>'points')::integer,0)),0)
      into penalty
    from jsonb_array_elements(player.rack) as rack(tile);

    if finisher is not null and player.user_id=finisher then
      continue;
    end if;

    scores := jsonb_set(
      scores,
      array[player.user_id::text],
      to_jsonb(coalesce((scores->>player.user_id::text)::integer,0)-penalty),
      true
    );
    finisher_bonus := finisher_bonus + penalty;
  end loop;

  if finisher is not null then
    scores := jsonb_set(
      scores,
      array[finisher::text],
      to_jsonb(coalesce((scores->>finisher::text)::integer,0)+finisher_bonus),
      true
    );
  end if;

  next_log := coalesce(target.game_state->'log','[]'::jsonb)
    || jsonb_build_array(jsonb_build_object(
      'type','finish',
      'reason',coalesce(end_reason,'finished'),
      'finisher',finisher,
      'at',now()
    ));

  update public.rooms
  set status='finished',
      game_state=target.game_state || jsonb_build_object(
        'phase','finished',
        'finished',true,
        'finish_reason',coalesce(end_reason,'finished'),
        'scores',scores,
        'log',next_log,
        'revision',coalesce((target.game_state->>'revision')::integer,0)+1
      ),
      updated_at=now()
  where id=target_room
  returning * into target;

  return target;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.place_scrabble_word(target_room uuid, expected_revision integer, placements jsonb, validated_words jsonb, actor uuid)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target public.rooms;
  private_row public.room_player_private;
  rack jsonb;
  board jsonb;
  candidate_board jsonb;
  placement jsonb;
  tile jsonb;
  cell_tile jsonb;
  p record;
  r integer;
  c integer;
  idx integer;
  min_axis integer;
  max_axis integer;
  fixed_axis integer;
  horizontal boolean;
  first_move boolean;
  connected boolean := false;
  new_positions integer[] := array[]::integer[];
  used_ids text[] := array[]::text[];
  computed_keys text[] := array[]::text[];
  computed_words text[] := array[]::text[];
  validated_array text[] := array[]::text[];
  words_json jsonb := '[]'::jsonb;
  rack_kept jsonb;
  rack_next jsonb;
  drawn jsonb := '[]'::jsonb;
  bag_row record;
  draw_count integer;
  axis integer;
  start_idx integer;
  cursor_idx integer;
  word_text text;
  word_len integer;
  subtotal integer;
  word_multiplier integer;
  tile_points integer;
  premium text;
  word_points integer;
  total_points integer := 0;
  bingo integer := 0;
  scores jsonb;
  player_ids jsonb;
  player_count integer;
  current_index integer;
  next_index integer := -1;
  next_user uuid;
  step integer;
  next_log jsonb;
  key_text text;
  i integer;
begin
  if actor is null then raise exception 'Sign in required'; end if;
  if jsonb_typeof(placements) is distinct from 'array'
     or jsonb_array_length(placements) < 1
     or jsonb_array_length(placements) > 7 then
    raise exception 'Place between 1 and 7 tiles';
  end if;
  if jsonb_typeof(validated_words) is distinct from 'array' then
    raise exception 'Invalid dictionary result';
  end if;

  select * into target from public.rooms where id=target_room for update;
  if not found or target.status <> 'playing' then raise exception 'Match is not active'; end if;
  if not exists(select 1 from public.room_members where room_id=target_room and user_id=actor and not is_withdrawn) then
    raise exception 'Active room membership required';
  end if;
  if coalesce((target.game_state->>'revision')::integer,0) <> expected_revision then
    raise exception 'Game state changed; refresh and try again';
  end if;

  player_ids := target.game_state->'player_ids';
  player_count := coalesce(jsonb_array_length(player_ids),0);
  current_index := coalesce((target.game_state->>'turn_index')::integer,-1);
  if player_count < 2 or current_index < 0 or current_index >= player_count
     or player_ids->>current_index <> actor::text then
    raise exception 'It is not your turn';
  end if;

  select * into private_row
  from public.room_player_private
  where room_id=target_room and user_id=actor
  for update;
  if not found then raise exception 'Your private rack was not found'; end if;
  rack := private_row.private_state->'rack';
  if jsonb_typeof(rack) is distinct from 'array' then raise exception 'Your rack is invalid'; end if;

  board := target.game_state->'board';
  if board is null or jsonb_typeof(board) is distinct from 'array' then
    raise exception 'The match board is invalid';
  end if;
  if jsonb_array_length(board)=0 then
    select jsonb_agg('null'::jsonb order by n) into board from generate_series(0,224) n;
  elsif jsonb_array_length(board)<>225 then
    raise exception 'The match board has an invalid size';
  end if;
  candidate_board := board;

  for p in select value from jsonb_array_elements(placements)
  loop
    if jsonb_typeof(p.value) is distinct from 'object'
       or coalesce((p.value->>'row')::integer,-1) not between 0 and 14
       or coalesce((p.value->>'col')::integer,-1) not between 0 and 14
       or nullif(p.value->>'tileId','') is null then
      raise exception 'Invalid tile placement';
    end if;
    r := (p.value->>'row')::integer;
    c := (p.value->>'col')::integer;
    idx := r*15+c;
    if idx = any(new_positions) then raise exception 'Two tiles cannot occupy the same square'; end if;
    if candidate_board->idx <> 'null'::jsonb then raise exception 'That square is already occupied'; end if;
    if (p.value->>'tileId') = any(used_ids) then raise exception 'A tile cannot be used twice'; end if;

    select value into tile
    from jsonb_array_elements(rack)
    where value->>'id'=p.value->>'tileId';
    if tile is null then raise exception 'A selected tile is not in your rack'; end if;

    if coalesce((tile->>'isBlank')::boolean,false) then
      if nullif(trim(p.value->>'blankAs'),'') is null or length(p.value->>'blankAs')>8 then
        raise exception 'Choose the letter represented by the blank tile';
      end if;
      tile := jsonb_set(tile,'{blankAs}',to_jsonb(trim(p.value->>'blankAs')),true);
      tile := jsonb_set(tile,'{points}','0'::jsonb,true);
    else
      tile := tile - 'blankAs';
    end if;

    candidate_board := jsonb_set(candidate_board,array[idx::text],tile,true);
    new_positions := array_append(new_positions,idx);
    used_ids := array_append(used_ids,p.value->>'tileId');
  end loop;

  first_move := not exists(
    select 1 from jsonb_array_elements(board) as cell(value)
    where cell.value <> 'null'::jsonb
  );

  horizontal := (select count(distinct (value->>'row'))=1 from jsonb_array_elements(placements));
  if not horizontal and (select count(distinct (value->>'col'))<>1 from jsonb_array_elements(placements)) then
    raise exception 'Tiles must be placed in one straight line';
  end if;

  if horizontal then
    select min((value->>'col')::integer),max((value->>'col')::integer),min((value->>'row')::integer)
    into min_axis,max_axis,fixed_axis from jsonb_array_elements(placements);
  else
    select min((value->>'row')::integer),max((value->>'row')::integer),min((value->>'col')::integer)
    into min_axis,max_axis,fixed_axis from jsonb_array_elements(placements);
  end if;

  for axis in min_axis..max_axis loop
    idx := case when horizontal then fixed_axis*15+axis else axis*15+fixed_axis end;
    if candidate_board->idx = 'null'::jsonb then raise exception 'There cannot be a gap between placed tiles'; end if;
  end loop;

  if first_move then
    if candidate_board->112='null'::jsonb then raise exception 'The first word must cover the center square'; end if;
  else
    foreach idx in array new_positions loop
      if (idx>=15 and board->(idx-15)<>'null'::jsonb)
         or (idx<210 and board->(idx+15)<>'null'::jsonb)
         or (idx%15>0 and board->(idx-1)<>'null'::jsonb)
         or (idx%15<14 and board->(idx+1)<>'null'::jsonb) then
        connected := true;
      end if;
    end loop;
    if not connected then raise exception 'Your word must connect to an existing tile'; end if;
  end if;

  -- Reconstruct every main/cross word from the authoritative board.
  for i in 1..2 loop
    foreach idx in array new_positions loop
      if i=1 then
        axis := 1; -- horizontal
      else
        axis := 15; -- vertical
      end if;
      start_idx := idx;
      while start_idx-axis>=0 and start_idx-axis<225 loop
        if (axis=1 and start_idx/15<>(start_idx-axis)/15) then exit; end if;
        if candidate_board->(start_idx-axis)='null'::jsonb then exit; end if;
        start_idx := start_idx-axis;
      end loop;
      cursor_idx := start_idx;
      word_text := '';
      word_len := 0;
      subtotal := 0;
      word_multiplier := 1;
      key_text := i::text||':'||start_idx::text;
      while cursor_idx>=0 and cursor_idx<225 loop
        if (axis=1 and cursor_idx/15<>start_idx/15) then exit; end if;
        cell_tile := candidate_board->cursor_idx;
        if cell_tile='null'::jsonb then exit; end if;
        word_text := word_text || coalesce(cell_tile->>'blankAs',cell_tile->>'letter','');
        word_len := word_len+1;
        tile_points := coalesce((cell_tile->>'points')::integer,0);
        if cursor_idx=any(new_positions) then
          premium := case
            when cursor_idx in (0,7,14,105,119,210,217,224) then 'TW'
            when cursor_idx in (18,26,32,42,46,58,64,70,112,154,160,166,178,182,192,198,206) then 'DW'
            when cursor_idx in (20,24,76,80,84,88,136,140,144,148,200,204) then 'TL'
            when cursor_idx in (3,11,36,38,45,52,59,92,96,98,102,108,116,122,126,128,132,165,172,179,186,188,213,221) then 'DL'
            else null end;
          if premium='DL' then tile_points:=tile_points*2; end if;
          if premium='TL' then tile_points:=tile_points*3; end if;
          if premium='DW' then word_multiplier:=word_multiplier*2; end if;
          if premium='TW' then word_multiplier:=word_multiplier*3; end if;
        end if;
        subtotal:=subtotal+tile_points;
        cursor_idx:=cursor_idx+axis;
      end loop;
      if word_len>1 and not (key_text=any(computed_keys)) then
        computed_keys:=array_append(computed_keys,key_text);
        computed_words:=array_append(computed_words,word_text);
        word_points:=subtotal*word_multiplier;
        total_points:=total_points+word_points;
        words_json:=words_json||jsonb_build_array(jsonb_build_object('word',word_text,'points',word_points,'start',start_idx,'direction',case when i=1 then 'horizontal' else 'vertical' end));
      end if;
    end loop;
  end loop;

  if cardinality(computed_words)=0 then raise exception 'The move must create at least one word'; end if;
  select coalesce(array_agg(distinct value order by value),array[]::text[])
  into validated_array from jsonb_array_elements_text(validated_words);
  if (select array_agg(distinct w order by w) from unnest(computed_words) w)
     is distinct from validated_array then
    raise exception 'Dictionary validation did not match the words on the board';
  end if;

  if cardinality(new_positions)=7 then bingo:=50; end if;
  total_points:=total_points+bingo;
  scores:=coalesce(target.game_state->'scores','{}'::jsonb);
  scores:=jsonb_set(scores,array[actor::text],to_jsonb(coalesce((scores->>actor::text)::integer,0)+total_points),true);

  select coalesce(jsonb_agg(value order by ordinality),'[]'::jsonb)
  into rack_kept
  from jsonb_array_elements(rack) with ordinality
  where not ((value->>'id')=any(used_ids));

  draw_count:=cardinality(new_positions);
  for bag_row in
    select position,tile from public.room_tile_bag
    where room_id=target_room order by position limit draw_count for update
  loop
    drawn:=drawn||jsonb_build_array(bag_row.tile);
    delete from public.room_tile_bag where room_id=target_room and position=bag_row.position;
  end loop;
  rack_next:=rack_kept||drawn;

  update public.room_player_private
  set private_state=jsonb_set(private_state,'{rack}',rack_next,true),updated_at=now()
  where room_id=target_room and user_id=actor;

  current_index:=coalesce((target.game_state->>'turn_index')::integer,0);
  next_user:=null;
  for step in 1..player_count loop
    next_index:=mod(current_index+step,player_count);
    next_user:=(player_ids->>next_index)::uuid;
    if exists(select 1 from public.room_members where room_id=target_room and user_id=next_user and not is_withdrawn) then exit; end if;
    next_user:=null;
  end loop;
  if next_user is null then raise exception 'No active players remain'; end if;

  next_log:=coalesce(target.game_state->'log','[]'::jsonb)||jsonb_build_array(
    jsonb_build_object('type','word','user_id',actor,'words',words_json,'points',total_points,'at',now())
  );

  update public.rooms
  set game_state=target.game_state||jsonb_build_object(
    'board',candidate_board,
    'scores',scores,
    'turn_index',next_index,
    'consecutive_passes',0,
    'remaining_tiles',(select count(*) from public.room_tile_bag where room_id=target_room),
    'log',next_log,
    'revision',expected_revision+1
  ),updated_at=now()
  where id=target_room returning * into target;
  if jsonb_array_length(rack_next)=0 and (select count(*) from public.room_tile_bag where room_id=target_room)=0 then
    return public.settle_scrabble_room(target_room,actor,'tiles_exhausted');
  end if;
  return target;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.pass_scrabble_turn(target_room uuid, expected_revision integer)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  target public.rooms;
  player_ids jsonb;
  current_index integer;
  next_index integer;
  player_count integer;
  step integer;
  next_user uuid;
  pass_count integer;
  active_count integer;
  next_log jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;

  select * into target
  from public.rooms
  where id=target_room
  for update;

  if not found or target.status <> 'playing' then
    raise exception 'Match is not active';
  end if;
  if not public.is_scrabble_room_member(target_room) then
    raise exception 'Room membership required';
  end if;
  if exists(
    select 1 from public.room_members
    where room_id=target_room and user_id=auth.uid() and is_withdrawn
  ) then
    raise exception 'Withdrawn players cannot take turns';
  end if;

  if coalesce((target.game_state->>'revision')::integer,0) <> expected_revision then
    raise exception 'Game state changed; refresh and try again';
  end if;

  player_ids := target.game_state->'player_ids';
  player_count := coalesce(jsonb_array_length(player_ids),0);
  current_index := coalesce((target.game_state->>'turn_index')::integer,-1);

  if player_count < 2 or current_index < 0 or current_index >= player_count then
    raise exception 'Match player order is invalid';
  end if;
  if player_ids->>current_index <> auth.uid()::text then
    raise exception 'It is not your turn';
  end if;

  next_index := -1;
  next_user := null;
  for step in 1..player_count loop
    next_index := mod(current_index + step, player_count);
    next_user := (player_ids->>next_index)::uuid;
    if exists(
      select 1 from public.room_members
      where room_id=target_room and user_id=next_user and not is_withdrawn
    ) then
      exit;
    end if;
    next_user := null;
  end loop;
  if next_user is null then
    raise exception 'No active players remain';
  end if;

  pass_count := coalesce((target.game_state->>'consecutive_passes')::integer,0)+1;
  next_log := coalesce(target.game_state->'log','[]'::jsonb)
    || jsonb_build_array(jsonb_build_object(
      'type','pass',
      'user_id',auth.uid(),
      'at',now()
    ));

  update public.rooms
  set game_state=target.game_state || jsonb_build_object(
        'turn_index',next_index,
        'consecutive_passes',pass_count,
        'log',next_log,
        'revision',expected_revision+1
      ),
      updated_at=now()
  where id=target_room
  returning * into target;

  select count(*) into active_count from public.room_members where room_id=target_room and not is_withdrawn;
  if pass_count >= active_count*2 then
    return public.settle_scrabble_room(target_room,null,'consecutive_passes');
  end if;
  return target;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.exchange_scrabble_tiles(target_room uuid, expected_revision integer, tile_ids uuid[])
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  target public.rooms;
  private_row public.room_player_private;
  rack_json jsonb;
  kept_rack jsonb;
  drawn_tiles jsonb := '[]'::jsonb;
  new_rack jsonb;
  selected_tile jsonb;
  selected_count integer;
  unique_count integer;
  bag_count integer;
  player_ids jsonb;
  player_count integer;
  current_index integer;
  next_index integer := -1;
  next_user uuid;
  step integer;
  pass_count integer;
  active_count integer;
  next_log jsonb;
  bag_position integer;
  bag_row record;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if tile_ids is null or cardinality(tile_ids) < 1 or cardinality(tile_ids) > 7 then
    raise exception 'Choose between 1 and 7 tiles';
  end if;
  selected_count := cardinality(tile_ids);
  select count(distinct selected_id) into unique_count
    from unnest(tile_ids) as selected(selected_id);
  if unique_count <> selected_count then raise exception 'Duplicate tile selection'; end if;

  select * into target from public.rooms where id=target_room for update;
  if not found or target.status <> 'playing' then raise exception 'Match is not active'; end if;
  if not public.is_scrabble_room_member(target_room) then raise exception 'Room membership required'; end if;
  if exists(select 1 from public.room_members where room_id=target_room and user_id=auth.uid() and is_withdrawn) then
    raise exception 'Withdrawn players cannot take turns';
  end if;
  if coalesce((target.game_state->>'revision')::integer,0) <> expected_revision then
    raise exception 'Game state changed; refresh and try again';
  end if;

  player_ids := target.game_state->'player_ids';
  player_count := coalesce(jsonb_array_length(player_ids),0);
  current_index := coalesce((target.game_state->>'turn_index')::integer,-1);
  if player_count < 2 or current_index < 0 or current_index >= player_count
     or player_ids->>current_index <> auth.uid()::text then
    raise exception 'It is not your turn';
  end if;

  select * into private_row from public.room_player_private
    where room_id=target_room and user_id=auth.uid() for update;
  if not found then raise exception 'Your private rack was not found'; end if;
  rack_json := private_row.private_state->'rack';
  if jsonb_typeof(rack_json) is distinct from 'array' then raise exception 'Your rack is invalid'; end if;
  if exists(
    select 1 from unnest(tile_ids) as chosen(id)
    where not exists(
      select 1 from jsonb_array_elements(rack_json) as rack(rack_tile)
      where rack.rack_tile->>'id'=chosen.id::text
    )
  ) then raise exception 'A selected tile is not in your rack'; end if;

  select count(*) into bag_count from public.room_tile_bag where room_id=target_room;
  if bag_count < 7 or bag_count < selected_count then raise exception 'At least seven tiles must remain in the bag to exchange'; end if;

  for bag_row in
    select position,tile from public.room_tile_bag
    where room_id=target_room order by position limit selected_count for update
  loop
    drawn_tiles := drawn_tiles || jsonb_build_array(bag_row.tile);
    delete from public.room_tile_bag where room_id=target_room and position=bag_row.position;
  end loop;
  if jsonb_array_length(drawn_tiles) <> selected_count then raise exception 'Could not draw replacement tiles'; end if;

  select coalesce(jsonb_agg(rack_tile order by ordinal), '[]'::jsonb)
    into kept_rack
    from jsonb_array_elements(rack_json) with ordinality as rack(rack_tile,ordinal)
    where not ((rack_tile->>'id') = any(array(select unnest(tile_ids)::text)));
  new_rack := kept_rack || drawn_tiles;

  select coalesce(max(position),0) into bag_position
    from public.room_tile_bag where room_id=target_room;
  for selected_tile in
    select rack_tile
    from jsonb_array_elements(rack_json) with ordinality as rack(rack_tile,ordinal)
    where (rack_tile->>'id') = any(array(select unnest(tile_ids)::text))
    order by ordinal
  loop
    bag_position := bag_position+1;
    insert into public.room_tile_bag(room_id,position,tile)
      values(target_room,bag_position,selected_tile);
  end loop;

  -- Return exchanged tiles to the bag, then shuffle the whole remaining bag.
  update public.room_tile_bag
    set position=position+bag_position+1000
    where room_id=target_room;
  with randomized as (
    select position,row_number() over(order by random())::integer as new_position
    from public.room_tile_bag where room_id=target_room
  )
  update public.room_tile_bag b
    set position=randomized.new_position
    from randomized
    where b.room_id=target_room and b.position=randomized.position;

  update public.room_player_private
    set private_state=private_row.private_state || jsonb_build_object('rack',new_rack),
        updated_at=now()
    where room_id=target_room and user_id=auth.uid();

  for step in 1..player_count loop
    next_index := mod(current_index+step,player_count);
    next_user := (player_ids->>next_index)::uuid;
    if exists(select 1 from public.room_members where room_id=target_room and user_id=next_user and not is_withdrawn) then
      exit;
    end if;
    next_user := null;
  end loop;
  if next_user is null then raise exception 'No active players remain'; end if;

  pass_count := coalesce((target.game_state->>'consecutive_passes')::integer,0)+1;
  next_log := coalesce(target.game_state->'log','[]'::jsonb)
    || jsonb_build_array(jsonb_build_object('type','exchange','user_id',auth.uid(),'count',selected_count,'at',now()));

  update public.rooms
    set game_state=target.game_state || jsonb_build_object(
      'turn_index',next_index,
      'consecutive_passes',pass_count,
      'remaining_tiles',(select count(*) from public.room_tile_bag where room_id=target_room),
      'log',next_log,
      'revision',expected_revision+1
    ),
    updated_at=now()
    where id=target_room returning * into target;
  select count(*) into active_count from public.room_members where room_id=target_room and not is_withdrawn;
  if pass_count >= active_count*2 then
    return public.settle_scrabble_room(target_room,null,'consecutive_passes');
  end if;
  return target;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.finish_scrabble_room(target_room uuid)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare target public.rooms;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into target from public.rooms where id=target_room for update;
  if not found then raise exception 'Room not found'; end if;
  if target.host_id <> auth.uid() then raise exception 'Only the host can finish the match'; end if;
  if target.status <> 'playing' then raise exception 'Match is not active'; end if;
  return public.settle_scrabble_room(target_room,null,'host');
end;
$function$
;

revoke all on function public.settle_scrabble_room(uuid,uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.place_scrabble_word(uuid,integer,jsonb,jsonb,uuid) from public, anon, authenticated;
grant execute on function public.place_scrabble_word(uuid,integer,jsonb,jsonb,uuid) to service_role;


-- Private server-managed cache for exact Arabic and English dictionary lookups.
create table if not exists public.scrabble_dictionary_cache (
  language text not null check (language in ('ar','en')),
  word text not null check (length(word) between 1 and 80),
  is_valid boolean not null,
  checked_at timestamptz not null default now(),
  primary key(language,word)
);
alter table public.scrabble_dictionary_cache enable row level security;
revoke all on public.scrabble_dictionary_cache from anon, authenticated;
grant select, insert, update on public.scrabble_dictionary_cache to service_role;

-- RLS performance: evaluate auth.uid() once per statement.
alter policy "direct message participants read" on public.direct_messages using (((sender_id = ( SELECT auth.uid() AS uid)) OR (recipient_id = ( SELECT auth.uid() AS uid))));
alter policy "send direct messages" on public.direct_messages with check (((sender_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM friendships f
  WHERE (((f.user_low = ( SELECT auth.uid() AS uid)) AND (f.user_high = direct_messages.recipient_id)) OR ((f.user_high = ( SELECT auth.uid() AS uid)) AND (f.user_low = direct_messages.recipient_id)))))));
alter policy "friend requests visible to participants" on public.friend_requests using (((sender_id = ( SELECT auth.uid() AS uid)) OR (receiver_id = ( SELECT auth.uid() AS uid))));
alter policy "receiver can update request" on public.friend_requests using (((receiver_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text))) with check (((receiver_id = ( SELECT auth.uid() AS uid)) AND (status = ANY (ARRAY['accepted'::text, 'rejected'::text]))));
alter policy "send friend requests" on public.friend_requests with check (((sender_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text)));
alter policy "friendships visible to participants" on public.friendships using (((user_low = ( SELECT auth.uid() AS uid)) OR (user_high = ( SELECT auth.uid() AS uid))));
alter policy "profiles readable by privacy settings" on public.profiles using (((id = ( SELECT auth.uid() AS uid)) OR (privacy = 'everyone'::text) OR ((privacy = 'friends'::text) AND (EXISTS ( SELECT 1
   FROM friendships f
  WHERE (((f.user_low = ( SELECT auth.uid() AS uid)) AND (f.user_high = profiles.id)) OR ((f.user_high = ( SELECT auth.uid() AS uid)) AND (f.user_low = profiles.id))))))));
alter policy "users update own profile" on public.profiles using ((id = ( SELECT auth.uid() AS uid))) with check ((id = ( SELECT auth.uid() AS uid)));
alter policy "receiver updates room invite" on public.room_invites using (((receiver_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text))) with check (((receiver_id = ( SELECT auth.uid() AS uid)) AND (status = ANY (ARRAY['accepted'::text, 'rejected'::text]))));
alter policy "room invite participants read" on public.room_invites using (((sender_id = ( SELECT auth.uid() AS uid)) OR (receiver_id = ( SELECT auth.uid() AS uid))));
alter policy "send room invites" on public.room_invites with check (((sender_id = ( SELECT auth.uid() AS uid)) AND is_scrabble_room_member(room_id)));
alter policy "users leave waiting or finished rooms" on public.room_members using (((user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = room_members.room_id) AND (r.status = ANY (ARRAY['waiting'::text, 'finished'::text])))))));
alter policy "room members send chat" on public.room_messages with check (((sender_id = ( SELECT auth.uid() AS uid)) AND is_scrabble_room_member(room_id)));
alter policy "players read only their private room state" on public.room_player_private using (((user_id = ( SELECT auth.uid() AS uid)) AND is_scrabble_room_member(room_id)));


-- Player progression and private match history.
alter table public.profiles
  add column if not exists xp integer not null default 0 check (xp >= 0),
  add column if not exists wins integer not null default 0 check (wins >= 0),
  add column if not exists losses integer not null default 0 check (losses >= 0),
  add column if not exists draws integer not null default 0 check (draws >= 0);
revoke update on public.profiles from authenticated;
grant update (username,bio,privacy,avatar_url,updated_at) on public.profiles to authenticated;

create table if not exists public.scrabble_match_results (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  language text not null check (language in ('ar','en')),
  score integer not null default 0,
  outcome text not null check (outcome in ('win','draw','loss')),
  xp_change integer not null,
  created_at timestamptz not null default now(),
  unique(room_id,user_id)
);
create index if not exists scrabble_match_results_user_created_idx
  on public.scrabble_match_results(user_id,created_at desc);
alter table public.scrabble_match_results enable row level security;
revoke all on public.scrabble_match_results from anon,authenticated;
grant select on public.scrabble_match_results to authenticated;
grant all on public.scrabble_match_results to service_role;
drop policy if exists "players read their own match results" on public.scrabble_match_results;
create policy "players read their own match results"
  on public.scrabble_match_results for select to authenticated
  using ((select auth.uid())=user_id);

create or replace function public.record_scrabble_match_result()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  score_map jsonb;
  best_score integer;
  best_count integer;
  participant record;
  final_outcome text;
  delta integer;
  inserted_id uuid;
begin
  if old.status <> 'playing' or new.status <> 'finished' then return new; end if;
  score_map := coalesce(new.game_state->'scores','{}'::jsonb);
  select max(coalesce((score_map->>m.user_id::text)::integer,0)),
         count(*) filter (where coalesce((score_map->>m.user_id::text)::integer,0)=
           (select max(coalesce((score_map->>m2.user_id::text)::integer,0))
            from public.room_members m2 where m2.room_id=new.id and not m2.is_withdrawn))
    into best_score,best_count
  from public.room_members m
  where m.room_id=new.id and not m.is_withdrawn;

  for participant in
    select m.user_id,coalesce((score_map->>m.user_id::text)::integer,0) as score
    from public.room_members m
    where m.room_id=new.id and not m.is_withdrawn
  loop
    if participant.score=best_score and best_count>1 then final_outcome := 'draw';
    elsif participant.score=best_score then final_outcome := 'win';
    else final_outcome := 'loss';
    end if;
    delta := case final_outcome when 'win' then 20 when 'draw' then 15 else -5 end;

    insert into public.scrabble_match_results
      (room_id,user_id,language,score,outcome,xp_change)
    values (new.id,participant.user_id,case when new.language='ar' then 'ar' else 'en' end,
      participant.score,final_outcome,delta)
    on conflict (room_id,user_id) do nothing
    returning id into inserted_id;

    if inserted_id is not null then
      update public.profiles
      set xp=greatest(0,xp+delta),
          wins=wins+case when final_outcome='win' then 1 else 0 end,
          draws=draws+case when final_outcome='draw' then 1 else 0 end,
          losses=losses+case when final_outcome='loss' then 1 else 0 end,
          updated_at=now()
      where id=participant.user_id;
      if not found then raise exception 'Profile missing for match participant'; end if;
    end if;
    inserted_id := null;
  end loop;
  return new;
end;
$function$;
revoke all on function public.record_scrabble_match_result() from public,anon,authenticated,service_role;
drop trigger if exists record_scrabble_match_result on public.rooms;
create trigger record_scrabble_match_result
after update of status on public.rooms
for each row when (old.status='playing' and new.status='finished')
execute function public.record_scrabble_match_result();
