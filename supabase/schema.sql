-- Scrabble cloud backend (Supabase / PostgreSQL)
-- Run this entire file in Supabase SQL Editor.
create extension if not exists pgcrypto;
create extension if not exists pg_cron with schema pg_catalog;

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
  is_withdrawn boolean not null default false,
  last_seen_at timestamptz not null default now(),
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

-- Heartbeats may update only the caller's timestamp, never membership or turn fields.
revoke update on public.room_members from authenticated;
grant update(last_seen_at) on public.room_members to authenticated;
drop policy if exists "players update own heartbeat" on public.room_members;
create policy "players update own heartbeat" on public.room_members for update to authenticated
using(user_id=auth.uid() and not is_withdrawn and exists(select 1 from public.rooms r where r.id=room_id and r.status='playing'))
with check(user_id=auth.uid() and not is_withdrawn and last_seen_at <= clock_timestamp()+interval '10 seconds' and exists(select 1 from public.rooms r where r.id=room_id and r.status='playing'));
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

-- Server-owned tile bag. Browser roles have no direct access; trusted RPCs own draws.
create table if not exists public.room_tile_bag (
  room_id uuid not null references public.rooms(id) on delete cascade,
  position integer not null,
  tile jsonb not null,
  primary key(room_id,position)
);
alter table public.room_tile_bag enable row level security;
revoke all on public.room_tile_bag from public, anon, authenticated;
grant all on public.room_tile_bag to service_role;


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
  add column if not exists is_withdrawn boolean not null default false,
  add column if not exists last_seen_at timestamptz not null default now();

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
  actual_delta integer;
  current_xp integer;
  inserted_id uuid;
begin
  if old.status <> 'playing' or new.status <> 'finished' then return new; end if;
  score_map := coalesce(new.game_state->'scores','{}'::jsonb);

  select max(coalesce((score_map->>m.user_id::text)::integer,0)),
         count(*) filter (where coalesce((score_map->>m.user_id::text)::integer,0)=
           (select max(coalesce((score_map->>m2.user_id::text)::integer,0))
            from public.room_members m2
            where m2.room_id=new.id and not m2.is_withdrawn))
    into best_score,best_count
  from public.room_members m
  where m.room_id=new.id and not m.is_withdrawn;

  for participant in
    select m.user_id,m.is_withdrawn,
           coalesce((score_map->>m.user_id::text)::integer,0) as score
    from public.room_members m
    where m.room_id=new.id
  loop
    if participant.is_withdrawn or best_score is null then
      final_outcome := 'loss';
    elsif participant.score=best_score and best_count>1 then
      final_outcome := 'draw';
    elsif participant.score=best_score then
      final_outcome := 'win';
    else
      final_outcome := 'loss';
    end if;
    delta := case final_outcome when 'win' then 20 when 'draw' then 15 else -5 end;

    select xp into current_xp
    from public.profiles where id=participant.user_id for update;
    if not found then raise exception 'Profile missing for match participant'; end if;
    actual_delta := greatest(0,current_xp+delta)-current_xp;

    insert into public.scrabble_match_results
      (room_id,user_id,language,score,outcome,xp_change)
    values (new.id,participant.user_id,case when new.language='ar' then 'ar' else 'en' end,
      participant.score,final_outcome,actual_delta)
    on conflict (room_id,user_id) do nothing
    returning id into inserted_id;

    if inserted_id is not null then
      update public.profiles
      set xp=current_xp+actual_delta,
          wins=wins+case when final_outcome='win' then 1 else 0 end,
          draws=draws+case when final_outcome='draw' then 1 else 0 end,
          losses=losses+case when final_outcome='loss' then 1 else 0 end,
          updated_at=now()
      where id=participant.user_id;
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


-- Withdrawals skip the current turn, transfer host control, and settle when one or zero players remain.

create or replace function public.withdraw_scrabble_room(target_room uuid)
returns public.rooms
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  target public.rooms;
  player_ids jsonb;
  player_count integer;
  current_index integer;
  next_index integer;
  next_user uuid;
  new_host uuid;
  step integer;
  active_count integer;
  next_log jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into target from public.rooms where id=target_room for update;
  if not found then raise exception 'Room not found'; end if;
  if target.status <> 'playing' then raise exception 'Match is not active'; end if;
  if not exists(select 1 from public.room_members
    where room_id=target_room and user_id=auth.uid() and not is_withdrawn) then
    raise exception 'Active room membership required';
  end if;

  update public.room_members set is_withdrawn=true,is_ready=false
  where room_id=target_room and user_id=auth.uid();

  select count(*) into active_count from public.room_members
  where room_id=target_room and not is_withdrawn;

  if active_count <= 1 then
    return public.settle_scrabble_room(
      target_room,null,
      case when active_count=0 then 'all_withdrawn' else 'last_player_remaining' end
    );
  end if;

  player_ids := target.game_state->'player_ids';
  player_count := coalesce(jsonb_array_length(player_ids),0);
  current_index := coalesce((target.game_state->>'turn_index')::integer,-1);
  next_index := current_index;
  if player_count < 2 or current_index < 0 or current_index >= player_count then
    raise exception 'Match player order is invalid';
  end if;

  if player_ids->>current_index=auth.uid()::text then
    next_user := null;
    for step in 1..player_count loop
      next_index := mod(current_index+step,player_count);
      next_user := (player_ids->>next_index)::uuid;
      if exists(select 1 from public.room_members
        where room_id=target_room and user_id=next_user and not is_withdrawn) then
        exit;
      end if;
      next_user := null;
    end loop;
    if next_user is null then raise exception 'No active players remain'; end if;
  end if;

  if target.host_id=auth.uid() then
    select user_id into new_host from public.room_members
    where room_id=target_room and not is_withdrawn order by seat limit 1;
  end if;

  next_log := coalesce(target.game_state->'log','[]'::jsonb)
    || jsonb_build_array(jsonb_build_object('type','withdraw','user_id',auth.uid(),'at',now()));

  update public.rooms
  set host_id=coalesce(new_host,host_id),
      game_state=target.game_state || jsonb_build_object(
        'turn_index',next_index,
        'revision',coalesce((target.game_state->>'revision')::integer,0)+1,
        'log',next_log
      ),updated_at=now()
  where id=target_room returning * into target;
  return target;
end;
$function$;

 
-- Server-enforced 120-second reconnect grace. The client refreshes last_seen_at
-- every 20 seconds while the active match is open. Cron expires only stale rows.
create index if not exists room_members_stale_heartbeat_idx
  on public.room_members(last_seen_at)
  where not is_withdrawn;

create or replace function public.initialize_scrabble_room_heartbeats()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  if old.status is distinct from new.status and new.status = 'playing' then
    update public.room_members set last_seen_at=clock_timestamp()
    where room_id=new.id and not is_withdrawn;
  end if;
  return new;
end;
$function$;
revoke all on function public.initialize_scrabble_room_heartbeats() from public,anon,authenticated,service_role;
drop trigger if exists initialize_scrabble_room_heartbeats on public.rooms;
create trigger initialize_scrabble_room_heartbeats
after update of status on public.rooms
for each row execute function public.initialize_scrabble_room_heartbeats();

create or replace function public.heartbeat_scrabble_room(target_room uuid)
returns void language plpgsql security invoker set search_path = ''
as $function$
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  update public.room_members m
    set last_seen_at=clock_timestamp()
    from public.rooms r
    where m.room_id=target_room and m.user_id=auth.uid()
      and not m.is_withdrawn and r.id=m.room_id and r.status='playing';
  if not found then raise exception 'Reconnect window expired or match is no longer active'; end if;
end;
$function$;
revoke all on function public.heartbeat_scrabble_room(uuid) from public,anon;
grant execute on function public.heartbeat_scrabble_room(uuid) to authenticated;

create or replace function public.expire_scrabble_disconnects()
returns integer language plpgsql security definer set search_path = ''
as $function$
declare
  candidate record;
  target public.rooms;
  member_row public.room_members;
  player_ids jsonb;
  player_count integer;
  current_index integer;
  next_index integer;
  next_user uuid;
  new_host uuid;
  step integer;
  active_count integer;
  next_log jsonb;
  expired_count integer := 0;
begin
  for candidate in
    select m.room_id,m.user_id
    from public.room_members m
    join public.rooms r on r.id=m.room_id
    where r.status='playing' and not m.is_withdrawn
      and m.last_seen_at < clock_timestamp()-interval '120 seconds'
    order by m.last_seen_at
  loop
    select * into target from public.rooms where id=candidate.room_id for update;
    if not found or target.status<>'playing' then continue; end if;

    select * into member_row from public.room_members
    where room_id=candidate.room_id and user_id=candidate.user_id for update;
    if not found or member_row.is_withdrawn
       or member_row.last_seen_at >= clock_timestamp()-interval '120 seconds' then
      continue;
    end if;

    update public.room_members set is_withdrawn=true,is_ready=false
    where room_id=candidate.room_id and user_id=candidate.user_id and not is_withdrawn;
    if not found then continue; end if;
    expired_count := expired_count+1;

    select count(*) into active_count from public.room_members
    where room_id=candidate.room_id and not is_withdrawn;
    if active_count<=1 then
      perform public.settle_scrabble_room(
        candidate.room_id,null,
        case when active_count=0 then 'all_disconnected' else 'disconnect_last_player' end
      );
      continue;
    end if;

    player_ids := target.game_state->'player_ids';
    player_count := case when jsonb_typeof(player_ids)='array'
      then jsonb_array_length(player_ids) else 0 end;
    current_index := coalesce((target.game_state->>'turn_index')::integer,-1);
    next_index := current_index;
    next_user := null;
    new_host := null;

    if player_count>0 and current_index>=0 and current_index<player_count
       and player_ids->>current_index=candidate.user_id::text then
      for step in 1..player_count loop
        next_index := mod(current_index+step,player_count);
        next_user := (player_ids->>next_index)::uuid;
        if exists(select 1 from public.room_members
          where room_id=candidate.room_id and user_id=next_user and not is_withdrawn) then
          exit;
        end if;
        next_user := null;
      end loop;
      if next_user is null then next_index:=current_index; end if;
    end if;

    if target.host_id=candidate.user_id then
      select user_id into new_host from public.room_members
      where room_id=candidate.room_id and not is_withdrawn order by seat limit 1;
    end if;

    next_log := coalesce(target.game_state->'log','[]'::jsonb)
      || jsonb_build_array(jsonb_build_object(
        'type','disconnect_expired','user_id',candidate.user_id,
        'grace_seconds',120,'at',clock_timestamp()
      ));

    update public.rooms
    set host_id=coalesce(new_host,host_id),
        game_state=target.game_state || jsonb_build_object(
          'turn_index',next_index,
          'revision',coalesce((target.game_state->>'revision')::integer,0)+1,
          'log',next_log
        ),
        updated_at=clock_timestamp()
    where id=candidate.room_id;
  end loop;
  return expired_count;
end;
$function$;
revoke all on function public.expire_scrabble_disconnects() from public,anon,authenticated,service_role;

select cron.schedule(
  'scrabble-reconnect-grace-expiry',
  '10 seconds',
  'select public.expire_scrabble_disconnects();'
);


-- Exact server-side tile distributions, first-player draw, and private rack dealing.
create or replace function public.scrabble_start_rank(p_letter text, p_language text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
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
$function$

create or replace function public.start_scrabble_room(target_room uuid)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$

grant execute on function public.start_scrabble_room(uuid) to authenticated;

-- Server-authoritative pass and exchange operations.
create or replace function public.pass_scrabble_turn(target_room uuid, expected_revision integer)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
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
$$;

grant execute on function public.pass_scrabble_turn(uuid,integer) to authenticated;

create or replace function public.exchange_scrabble_tiles(target_room uuid, expected_revision integer, tile_ids uuid[])
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $exchange$
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
$exchange$;

grant execute on function public.exchange_scrabble_tiles(uuid,integer,uuid[]) to authenticated;
revoke all on function public.exchange_scrabble_tiles(uuid,integer,uuid[]) from public, anon;

 
-- Privacy-safe aggregate leaderboards. Raw match history remains private to its owner.
create table if not exists public.scrabble_leaderboard_periods (
  user_id uuid not null references public.profiles(id) on delete cascade,
  language text not null check(language in ('ar','en','all')),
  period_type text not null check(period_type in ('all_time','weekly','monthly')),
  period_start date not null,
  xp_change integer not null default 0,
  wins integer not null default 0,
  draws integer not null default 0,
  losses integer not null default 0,
  games integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key(user_id,language,period_type,period_start),
  check (
    (period_type='all_time' and period_start=date '0001-01-01')
    or (period_type<>'all_time' and period_start<>date '0001-01-01')
  )
);
create index if not exists scrabble_leaderboard_period_lookup_idx
  on public.scrabble_leaderboard_periods(period_type,language,period_start,xp_change desc,wins desc);
alter table public.scrabble_leaderboard_periods enable row level security;
drop policy if exists "public leaderboard aggregates visible" on public.scrabble_leaderboard_periods;
create policy "public leaderboard aggregates visible"
  on public.scrabble_leaderboard_periods for select to authenticated
  using (exists(
    select 1 from public.profiles p
    where p.id=scrabble_leaderboard_periods.user_id and p.privacy='everyone'
  ));
revoke all on public.scrabble_leaderboard_periods from anon,authenticated;
grant select on public.scrabble_leaderboard_periods to authenticated;

create or replace function public.aggregate_scrabble_leaderboard_periods()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  week_start date := date_trunc('week',new.created_at at time zone 'UTC')::date;
  month_start date := date_trunc('month',new.created_at at time zone 'UTC')::date;
  win_count integer := case when new.outcome='win' then 1 else 0 end;
  draw_count integer := case when new.outcome='draw' then 1 else 0 end;
  loss_count integer := case when new.outcome='loss' then 1 else 0 end;
begin
  insert into public.scrabble_leaderboard_periods
    (user_id,language,period_type,period_start,xp_change,wins,draws,losses,games,updated_at)
  values
    (new.user_id,new.language,'all_time',date '0001-01-01',new.xp_change,win_count,draw_count,loss_count,1,now()),
    (new.user_id,'all','all_time',date '0001-01-01',new.xp_change,win_count,draw_count,loss_count,1,now()),
    (new.user_id,new.language,'weekly',week_start,new.xp_change,win_count,draw_count,loss_count,1,now()),
    (new.user_id,'all','weekly',week_start,new.xp_change,win_count,draw_count,loss_count,1,now()),
    (new.user_id,new.language,'monthly',month_start,new.xp_change,win_count,draw_count,loss_count,1,now()),
    (new.user_id,'all','monthly',month_start,new.xp_change,win_count,draw_count,loss_count,1,now())
  on conflict(user_id,language,period_type,period_start) do update
  set xp_change=public.scrabble_leaderboard_periods.xp_change+excluded.xp_change,
      wins=public.scrabble_leaderboard_periods.wins+excluded.wins,
      draws=public.scrabble_leaderboard_periods.draws+excluded.draws,
      losses=public.scrabble_leaderboard_periods.losses+excluded.losses,
      games=public.scrabble_leaderboard_periods.games+excluded.games,
      updated_at=now();
  return new;
end;
$function$;
revoke all on function public.aggregate_scrabble_leaderboard_periods() from public,anon,authenticated,service_role;
drop trigger if exists aggregate_scrabble_leaderboard_periods on public.scrabble_match_results;
create trigger aggregate_scrabble_leaderboard_periods
after insert on public.scrabble_match_results
for each row execute function public.aggregate_scrabble_leaderboard_periods();

-- Backfill existing completed games, safe to re-run.
insert into public.scrabble_leaderboard_periods
  (user_id,language,period_type,period_start,xp_change,wins,draws,losses,games)
select user_id,language,'all_time',date '0001-01-01',sum(xp_change),
       count(*) filter(where outcome='win'),count(*) filter(where outcome='draw'),
       count(*) filter(where outcome='loss'),count(*)
from public.scrabble_match_results group by user_id,language
on conflict do nothing;
insert into public.scrabble_leaderboard_periods
  (user_id,language,period_type,period_start,xp_change,wins,draws,losses,games)
select user_id,'all','all_time',date '0001-01-01',sum(xp_change),
       count(*) filter(where outcome='win'),count(*) filter(where outcome='draw'),
       count(*) filter(where outcome='loss'),count(*)
from public.scrabble_match_results group by user_id
on conflict do nothing;
insert into public.scrabble_leaderboard_periods
  (user_id,language,period_type,period_start,xp_change,wins,draws,losses,games)
select user_id,language,'weekly',date_trunc('week',created_at at time zone 'UTC')::date,sum(xp_change),
       count(*) filter(where outcome='win'),count(*) filter(where outcome='draw'),
       count(*) filter(where outcome='loss'),count(*)
from public.scrabble_match_results
group by user_id,language,date_trunc('week',created_at at time zone 'UTC')::date
on conflict do nothing;
insert into public.scrabble_leaderboard_periods
  (user_id,language,period_type,period_start,xp_change,wins,draws,losses,games)
select user_id,'all','weekly',date_trunc('week',created_at at time zone 'UTC')::date,sum(xp_change),
       count(*) filter(where outcome='win'),count(*) filter(where outcome='draw'),
       count(*) filter(where outcome='loss'),count(*)
from public.scrabble_match_results
group by user_id,date_trunc('week',created_at at time zone 'UTC')::date
on conflict do nothing;
insert into public.scrabble_leaderboard_periods
  (user_id,language,period_type,period_start,xp_change,wins,draws,losses,games)
select user_id,language,'monthly',date_trunc('month',created_at at time zone 'UTC')::date,sum(xp_change),
       count(*) filter(where outcome='win'),count(*) filter(where outcome='draw'),
       count(*) filter(where outcome='loss'),count(*)
from public.scrabble_match_results
group by user_id,language,date_trunc('month',created_at at time zone 'UTC')::date
on conflict do nothing;
insert into public.scrabble_leaderboard_periods
  (user_id,language,period_type,period_start,xp_change,wins,draws,losses,games)
select user_id,'all','monthly',date_trunc('month',created_at at time zone 'UTC')::date,sum(xp_change),
       count(*) filter(where outcome='win'),count(*) filter(where outcome='draw'),
       count(*) filter(where outcome='loss'),count(*)
from public.scrabble_match_results
group by user_id,date_trunc('month',created_at at time zone 'UTC')::date
on conflict do nothing;


-- Dictionary lookup cache is service-role only; clients cannot write dictionary verdicts.
create table if not exists public.scrabble_dictionary_cache (
  language text not null check(language in ('ar','en')),
  word text not null check(char_length(word) between 1 and 80),
  is_valid boolean not null,
  checked_at timestamptz not null default now(),
  primary key(language,word)
);
alter table public.scrabble_dictionary_cache enable row level security;
revoke all on public.scrabble_dictionary_cache from public,anon,authenticated;
grant all on public.scrabble_dictionary_cache to service_role;

-- Live authoritative word-placement RPC mirrored from the deployed database.
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
revoke all on function public.place_scrabble_word(uuid,integer,jsonb,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.place_scrabble_word(uuid,integer,jsonb,jsonb,uuid) to service_role;

 
-- Daily challenges: match results are the only source of progress.
create table if not exists public.scrabble_daily_challenge_progress (
  user_id uuid not null references public.profiles(id) on delete cascade,
  challenge_date date not null,
  challenge_id text not null check (challenge_id in ('play_match','win_match','score_100')),
  progress integer not null default 0 check (progress >= 0),
  goal integer not null default 1 check (goal > 0),
  reward_xp integer not null check (reward_xp > 0),
  claimed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, challenge_date, challenge_id)
);
alter table public.scrabble_daily_challenge_progress enable row level security;
revoke all on public.scrabble_daily_challenge_progress from public, anon, authenticated;
grant select on public.scrabble_daily_challenge_progress to authenticated;
drop policy if exists "players read own daily challenge progress" on public.scrabble_daily_challenge_progress;
create policy "players read own daily challenge progress"
on public.scrabble_daily_challenge_progress for select to authenticated
using ((select auth.uid()) = user_id);

create or replace function public.track_scrabble_daily_challenges()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare day_utc date := (new.created_at at time zone 'UTC')::date;
begin
  insert into public.scrabble_daily_challenge_progress
    (user_id, challenge_date, challenge_id, progress, goal, reward_xp)
  values
    (new.user_id, day_utc, 'play_match', 1, 1, 10),
    (new.user_id, day_utc, 'win_match', case when new.outcome = 'win' then 1 else 0 end, 1, 20),
    (new.user_id, day_utc, 'score_100', case when new.score >= 100 then 1 else 0 end, 1, 15)
  on conflict (user_id, challenge_date, challenge_id) do update
  set progress = least(public.scrabble_daily_challenge_progress.goal,
      public.scrabble_daily_challenge_progress.progress + excluded.progress),
      updated_at = now();
  return new;
end;
$function$;
revoke all on function public.track_scrabble_daily_challenges() from public, anon, authenticated, service_role;
drop trigger if exists track_scrabble_daily_challenges on public.scrabble_match_results;
create trigger track_scrabble_daily_challenges after insert on public.scrabble_match_results
for each row execute function public.track_scrabble_daily_challenges();

create or replace function public.claim_scrabble_daily_challenge(target_date date, target_challenge text)
returns integer language plpgsql security definer set search_path = ''
as $function$
declare uid uuid := auth.uid(); challenge public.scrabble_daily_challenge_progress;
begin
  if uid is null then raise exception 'Sign in required'; end if;
  select * into challenge from public.scrabble_daily_challenge_progress
  where user_id=uid and challenge_date=target_date and challenge_id=target_challenge for update;
  if not found then raise exception 'Challenge not found'; end if;
  if challenge.progress < challenge.goal then raise exception 'Challenge is not complete'; end if;
  if challenge.claimed_at is not null then raise exception 'Reward already claimed'; end if;
  update public.scrabble_daily_challenge_progress set claimed_at=now(),updated_at=now()
  where user_id=uid and challenge_date=target_date and challenge_id=target_challenge;
  update public.profiles set xp=xp+challenge.reward_xp,updated_at=now() where id=uid;
  return challenge.reward_xp;
end;
$function$;
revoke all on function public.claim_scrabble_daily_challenge(date,text) from public, anon;
grant execute on function public.claim_scrabble_daily_challenge(date,text) to authenticated;


-- Private in-app notifications for friend requests, room invites, and direct messages.
create table if not exists public.scrabble_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  kind text not null check (kind in ('friend_request','room_invite','direct_message','turn_started','match_result','daily_reward')),
  reference_id uuid,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists scrabble_notifications_user_created_idx
  on public.scrabble_notifications(user_id, created_at desc);
alter table public.scrabble_notifications enable row level security;
revoke all on public.scrabble_notifications from anon, authenticated;
grant select on public.scrabble_notifications to authenticated;
create policy "players read their own notifications"
  on public.scrabble_notifications for select to authenticated
  using ((select auth.uid()) = user_id);
grant update(read_at) on public.scrabble_notifications to authenticated;
drop policy if exists "players mark their own notifications read" on public.scrabble_notifications;
create policy "players mark their own notifications read"
on public.scrabble_notifications for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);


create or replace function public.mark_scrabble_notification_read(notification_id uuid)
returns void language plpgsql security invoker set search_path = public
as $
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  update public.scrabble_notifications
     set read_at = coalesce(read_at, now())
   where id = notification_id and user_id = auth.uid();
end;
$;
revoke all on function public.mark_scrabble_notification_read(uuid) from public, anon;
grant execute on function public.mark_scrabble_notification_read(uuid) to authenticated;

create or replace function public.emit_scrabble_notification()
returns trigger language plpgsql security definer set search_path = public
as $$
declare target_user uuid; actor uuid; event_kind text;
begin
  if tg_table_name = 'friend_requests' then
    target_user := new.receiver_id; actor := new.sender_id; event_kind := 'friend_request';
  elsif tg_table_name = 'room_invites' then
    target_user := new.receiver_id; actor := new.sender_id; event_kind := 'room_invite';
  elsif tg_table_name = 'direct_messages' then
    target_user := new.recipient_id; actor := new.sender_id; event_kind := 'direct_message';
  else
    return new;
  end if;
  if target_user is not null and target_user <> actor then
    insert into public.scrabble_notifications(user_id, actor_id, kind, reference_id)
    values (target_user, actor, event_kind, new.id);
  end if;
  return new;
end;
$$;
revoke all on function public.emit_scrabble_notification() from public, anon, authenticated;
drop trigger if exists notify_scrabble_friend_request on public.friend_requests;
create trigger notify_scrabble_friend_request after insert on public.friend_requests
for each row execute function public.emit_scrabble_notification();
drop trigger if exists notify_scrabble_room_invite on public.room_invites;
create trigger notify_scrabble_room_invite after insert on public.room_invites
for each row execute function public.emit_scrabble_notification();
drop trigger if exists notify_scrabble_direct_message on public.direct_messages;
create trigger notify_scrabble_direct_message after insert on public.direct_messages
for each row execute function public.emit_scrabble_notification();
alter publication supabase_realtime add table public.scrabble_notifications;


alter table public.scrabble_notifications drop constraint if exists scrabble_notifications_kind_check;
alter table public.scrabble_notifications add constraint scrabble_notifications_kind_check
 check (kind in ('friend_request','room_invite','direct_message','turn_started','match_result','daily_reward'));
create or replace function public.notify_scrabble_room_state()
returns trigger language plpgsql security definer set search_path=public
as $$
declare turn_user uuid; member_row record;
begin
 if new.status='playing' and (
   old.status is distinct from 'playing' or
   old.game_state->>'turn_index' is distinct from new.game_state->>'turn_index'
 ) then
   begin
     turn_user := (new.game_state->'player_ids'->>(coalesce((new.game_state->>'turn_index')::integer,0)))::uuid;
   exception when others then turn_user := null;
   end;
   if turn_user is not null then
     insert into public.scrabble_notifications(user_id,kind,reference_id)
     values(turn_user,'turn_started',new.id);
   end if;
 end if;
 if new.status='finished' and old.status is distinct from 'finished' then
   for member_row in select user_id from public.room_members where room_id=new.id loop
     insert into public.scrabble_notifications(user_id,kind,reference_id)
     values(member_row.user_id,'match_result',new.id);
   end loop;
 end if;
 return new;
end;
$$;
revoke all on function public.notify_scrabble_room_state() from public,anon,authenticated;
drop trigger if exists notify_scrabble_turn_and_result on public.rooms;
create trigger notify_scrabble_turn_and_result after update of status,game_state on public.rooms
for each row execute function public.notify_scrabble_room_state();

create or replace function public.notify_scrabble_daily_reward()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 if old.claimed_at is null and new.claimed_at is not null then
   insert into public.scrabble_notifications(user_id,kind,reference_id)
   values(new.user_id,'daily_reward',new.user_id);
 end if;
 return new;
end;
$$;
revoke all on function public.notify_scrabble_daily_reward() from public,anon,authenticated;
drop trigger if exists notify_scrabble_daily_reward on public.scrabble_daily_challenge_progress;
create trigger notify_scrabble_daily_reward after update of claimed_at on public.scrabble_daily_challenge_progress
for each row execute function public.notify_scrabble_daily_reward();


create table if not exists public.scrabble_store_catalog (
 item_key text primary key,
 category text not null check(category in ('frame','tiles','board','title')),
 name_ar text not null,
 name_en text not null,
 price integer not null check(price>0),
 active boolean not null default true
);
insert into public.scrabble_store_catalog(item_key,category,name_ar,name_en,price) values
 ('frame_gold','frame','إطار ذهبي','Golden frame',30),
 ('frame_royal','frame','إطار ملكي','Royal frame',60),
 ('tiles_wood','tiles','قطع خشبية','Wooden tiles',40),
 ('tiles_crystal','tiles','قطع كريستالية','Crystal tiles',80),
 ('board_classic','board','لوحة كلاسيكية','Classic board',50),
 ('board_night','board','لوحة ليلية','Night board',75),
 ('title_wordmaster','title','لقب خبير الكلمات','Word master title',25),
 ('title_champion','title','لقب البطل','Champion title',50)
on conflict(item_key) do nothing;
create table if not exists public.scrabble_wallets(user_id uuid primary key references public.profiles(id) on delete cascade,coins integer not null default 100 check(coins>=0),updated_at timestamptz not null default now());
create table if not exists public.scrabble_inventory(user_id uuid not null references public.profiles(id) on delete cascade,item_key text not null references public.scrabble_store_catalog(item_key),purchased_at timestamptz not null default now(),primary key(user_id,item_key));
alter table public.scrabble_store_catalog enable row level security;
alter table public.scrabble_wallets enable row level security;
alter table public.scrabble_inventory enable row level security;
revoke all on public.scrabble_store_catalog,public.scrabble_wallets,public.scrabble_inventory from anon,authenticated;
grant select on public.scrabble_store_catalog,public.scrabble_wallets,public.scrabble_inventory to authenticated;
drop policy if exists "active scrabble store catalog visible" on public.scrabble_store_catalog;
create policy "active scrabble store catalog visible" on public.scrabble_store_catalog for select to authenticated using(active);
drop policy if exists "players read own scrabble wallet" on public.scrabble_wallets;
create policy "players read own scrabble wallet" on public.scrabble_wallets for select to authenticated using((select auth.uid())=user_id);
drop policy if exists "players read own scrabble inventory" on public.scrabble_inventory;
create policy "players read own scrabble inventory" on public.scrabble_inventory for select to authenticated using((select auth.uid())=user_id);
create or replace function public.purchase_scrabble_store_item(target_item text)
returns integer language plpgsql security definer set search_path=public
as $$
declare uid uuid:=auth.uid(); item public.scrabble_store_catalog; balance integer;
begin
 if uid is null then raise exception 'Sign in required'; end if;
 select * into item from public.scrabble_store_catalog where item_key=target_item and active=true;
 if not found then raise exception 'Store item unavailable'; end if;
 insert into public.scrabble_wallets(user_id,coins) values(uid,100) on conflict(user_id) do nothing;
 select coins into balance from public.scrabble_wallets where user_id=uid for update;
 if exists(select 1 from public.scrabble_inventory where user_id=uid and item_key=target_item) then raise exception 'Item already owned'; end if;
 if balance<item.price then raise exception 'Not enough coins'; end if;
 update public.scrabble_wallets set coins=coins-item.price,updated_at=now() where user_id=uid returning coins into balance;
 insert into public.scrabble_inventory(user_id,item_key) values(uid,target_item);
 return balance;
end;
$$;
revoke all on function public.purchase_scrabble_store_item(text) from public,anon;
grant execute on function public.purchase_scrabble_store_item(text) to authenticated;


create table if not exists public.scrabble_gifts(
 id uuid primary key default gen_random_uuid(),
 sender_id uuid not null references public.profiles(id) on delete cascade,
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 item_key text not null references public.scrabble_store_catalog(item_key),
 status text not null default 'pending' check(status in ('pending','accepted','rejected')),
 created_at timestamptz not null default now(),
 resolved_at timestamptz,
 check(sender_id<>recipient_id)
);
alter table public.scrabble_gifts enable row level security;
revoke all on public.scrabble_gifts from anon,authenticated;
grant select on public.scrabble_gifts to authenticated;
drop policy if exists "players read their own gifts" on public.scrabble_gifts;
create policy "players read their own gifts" on public.scrabble_gifts for select to authenticated
using((select auth.uid())=sender_id or (select auth.uid())=recipient_id);
create or replace function public.send_scrabble_gift(recipient uuid,target_item text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare uid uuid:=auth.uid(); gift_id uuid;
begin
 if uid is null then raise exception 'Sign in required'; end if;
 if recipient is null or recipient=uid then raise exception 'Choose another player'; end if;
 if not exists(select 1 from public.friendships where user_low=least(uid,recipient) and user_high=greatest(uid,recipient)) then raise exception 'Gifts can only be sent to friends'; end if;
 if exists(select 1 from public.scrabble_inventory where user_id=recipient and item_key=target_item) then raise exception 'Friend already owns this item'; end if;
 perform 1 from public.scrabble_inventory where user_id=uid and item_key=target_item for update;
 if not found then raise exception 'You do not own this item'; end if;
 delete from public.scrabble_inventory where user_id=uid and item_key=target_item;
 insert into public.scrabble_gifts(sender_id,recipient_id,item_key) values(uid,recipient,target_item) returning id into gift_id;
 return gift_id;
end;
$$;
revoke all on function public.send_scrabble_gift(uuid,text) from public,anon;
grant execute on function public.send_scrabble_gift(uuid,text) to authenticated;
create or replace function public.resolve_scrabble_gift(target_gift uuid,accept_gift boolean)
returns void language plpgsql security definer set search_path=public
as $$
declare uid uuid:=auth.uid(); gift public.scrabble_gifts;
begin
 if uid is null then raise exception 'Sign in required'; end if;
 select * into gift from public.scrabble_gifts where id=target_gift and recipient_id=uid and status='pending' for update;
 if not found then raise exception 'Gift not available'; end if;
 if accept_gift then
   insert into public.scrabble_inventory(user_id,item_key) values(uid,gift.item_key) on conflict(user_id,item_key) do nothing;
   update public.scrabble_gifts set status='accepted',resolved_at=now() where id=target_gift;
 else
   insert into public.scrabble_inventory(user_id,item_key) values(gift.sender_id,gift.item_key) on conflict(user_id,item_key) do nothing;
   update public.scrabble_gifts set status='rejected',resolved_at=now() where id=target_gift;
 end if;
end;
$$;
revoke all on function public.resolve_scrabble_gift(uuid,boolean) from public,anon;
grant execute on function public.resolve_scrabble_gift(uuid,boolean) to authenticated;
alter table public.scrabble_notifications drop constraint if exists scrabble_notifications_kind_check;
alter table public.scrabble_notifications add constraint scrabble_notifications_kind_check
check(kind in ('friend_request','room_invite','direct_message','turn_started','match_result','daily_reward','gift_received'));
create or replace function public.notify_scrabble_gift_received()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 insert into public.scrabble_notifications(user_id,actor_id,kind,reference_id)
 values(new.recipient_id,new.sender_id,'gift_received',new.id);
 return new;
end;
$$;
revoke all on function public.notify_scrabble_gift_received() from public,anon,authenticated;
drop trigger if exists notify_scrabble_gift_received on public.scrabble_gifts;
create trigger notify_scrabble_gift_received after insert on public.scrabble_gifts
for each row execute function public.notify_scrabble_gift_received();


create table if not exists public.scrabble_user_settings(
 user_id uuid primary key references public.profiles(id) on delete cascade,
 language text not null default 'ar' check(language in ('ar','en')),
 dark_mode boolean not null default false,
 sound_enabled boolean not null default true,
 notification_preferences jsonb not null default '{"requests":true,"invites":true,"turns":true,"results":true,"daily":true,"tournaments":true,"messages":true,"rewards":true,"online":true}'::jsonb,
 updated_at timestamptz not null default now()
);
alter table public.scrabble_user_settings enable row level security;
revoke all on public.scrabble_user_settings from anon,authenticated;
grant select,insert,update on public.scrabble_user_settings to authenticated;
drop policy if exists "players read own scrabble settings" on public.scrabble_user_settings;
create policy "players read own scrabble settings" on public.scrabble_user_settings for select to authenticated using((select auth.uid())=user_id);
drop policy if exists "players create own scrabble settings" on public.scrabble_user_settings;
create policy "players create own scrabble settings" on public.scrabble_user_settings for insert to authenticated with check((select auth.uid())=user_id);
drop policy if exists "players update own scrabble settings" on public.scrabble_user_settings;
create policy "players update own scrabble settings" on public.scrabble_user_settings for update to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);

-- Room host removal and democratic voting.

create schema if not exists private;
create table if not exists public.scrabble_room_removal_votes(
 id uuid primary key default gen_random_uuid(), room_id uuid not null references public.rooms(id) on delete cascade,
 target_user_id uuid not null references public.profiles(id) on delete cascade, started_by uuid not null references public.profiles(id) on delete cascade,
 status text not null default 'open' check(status in ('open','approved','rejected','cancelled')), created_at timestamptz not null default now(), resolved_at timestamptz
);
create unique index if not exists one_open_scrabble_removal_vote_per_room on public.scrabble_room_removal_votes(room_id) where status='open';
create table if not exists public.scrabble_room_removal_ballots(
 vote_id uuid not null references public.scrabble_room_removal_votes(id) on delete cascade,
 voter_id uuid not null references public.profiles(id) on delete cascade, approve boolean not null, created_at timestamptz not null default now(),
 primary key(vote_id,voter_id)
);
alter table public.scrabble_room_removal_votes enable row level security;
alter table public.scrabble_room_removal_ballots enable row level security;
revoke all on public.scrabble_room_removal_votes,public.scrabble_room_removal_ballots from anon,authenticated;
grant select on public.scrabble_room_removal_votes,public.scrabble_room_removal_ballots to authenticated;
drop policy if exists "room members read removal votes" on public.scrabble_room_removal_votes;
create policy "room members read removal votes" on public.scrabble_room_removal_votes for select to authenticated using(public.is_scrabble_room_member(room_id));
drop policy if exists "room members read removal ballots" on public.scrabble_room_removal_ballots;
create policy "room members read removal ballots" on public.scrabble_room_removal_ballots for select to authenticated using(exists(select 1 from public.scrabble_room_removal_votes v where v.id=vote_id and public.is_scrabble_room_member(v.room_id)));
create or replace function private.apply_scrabble_room_removal(p_room uuid,p_target uuid,p_reason text)
returns public.rooms language plpgsql security definer set search_path=''
as $$
declare r public.rooms; current_idx integer; player_ids jsonb; count_players integer; step integer; next_idx integer; next_uid uuid; active_count integer; log_items jsonb;
begin
 select * into r from public.rooms where id=p_room for update;
 if not found then raise exception 'Room not found'; end if;
 if r.status not in ('waiting','playing') then raise exception 'Room is not active'; end if;
 if not exists(select 1 from public.room_members where room_id=p_room and user_id=p_target and not is_withdrawn) then raise exception 'Player is not active in this room'; end if;
 if p_target=r.host_id then raise exception 'The room host cannot be removed by this action'; end if;
 if r.status='waiting' then delete from public.room_members where room_id=p_room and user_id=p_target; update public.rooms set updated_at=now() where id=p_room returning * into r; return r; end if;
 update public.room_members set is_withdrawn=true,is_ready=false where room_id=p_room and user_id=p_target;
 select count(*) into active_count from public.room_members where room_id=p_room and not is_withdrawn;
 if active_count<=1 then return public.settle_scrabble_room(p_room,null,case when active_count=0 then 'all_withdrawn' else 'last_player_remaining' end); end if;
 player_ids:=r.game_state->'player_ids'; count_players:=coalesce(jsonb_array_length(player_ids),0); current_idx:=coalesce((r.game_state->>'turn_index')::integer,-1); next_idx:=current_idx;
 if count_players<2 or current_idx<0 or current_idx>=count_players then raise exception 'Match player order is invalid'; end if;
 if player_ids->>current_idx=p_target::text then
   next_uid:=null;
   for step in 1..count_players loop next_idx:=mod(current_idx+step,count_players); next_uid:=(player_ids->>next_idx)::uuid;
     if exists(select 1 from public.room_members where room_id=p_room and user_id=next_uid and not is_withdrawn) then exit; end if; next_uid:=null;
   end loop;
   if next_uid is null then raise exception 'No active players remain'; end if;
 end if;
 log_items:=coalesce(r.game_state->'log','[]'::jsonb)||jsonb_build_array(jsonb_build_object('type',p_reason,'user_id',p_target,'at',now()));
 update public.rooms set game_state=r.game_state||jsonb_build_object('turn_index',next_idx,'revision',coalesce((r.game_state->>'revision')::integer,0)+1,'log',log_items),updated_at=now() where id=p_room returning * into r;
 return r;
end;
$$;
revoke all on function private.apply_scrabble_room_removal(uuid,uuid,text) from public,anon,authenticated;
create or replace function public.host_kick_scrabble_room_player(target_room uuid,target_player uuid)
returns public.rooms language plpgsql security definer set search_path=''
as $$ declare r public.rooms; begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into r from public.rooms where id=target_room for update;
 if not found then raise exception 'Room not found'; end if;
 if r.host_id<>auth.uid() then raise exception 'Only the host can remove a player'; end if;
 if target_player=auth.uid() then raise exception 'Host cannot kick themselves'; end if;
 return private.apply_scrabble_room_removal(target_room,target_player,'host_kick');
end; $$;
revoke all on function public.host_kick_scrabble_room_player(uuid,uuid) from public,anon;
grant execute on function public.host_kick_scrabble_room_player(uuid,uuid) to authenticated;
create or replace function public.start_scrabble_room_removal_vote(target_room uuid,target_player uuid)
returns uuid language plpgsql security definer set search_path=''
as $$ declare r public.rooms; vote_id uuid; active_count integer; begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into r from public.rooms where id=target_room for update;
 if not found or r.status not in ('waiting','playing') then raise exception 'Room is not active'; end if;
 if not exists(select 1 from public.room_members where room_id=target_room and user_id=auth.uid() and not is_withdrawn) then raise exception 'Active room membership required'; end if;
 if target_player=auth.uid() then raise exception 'You cannot vote to remove yourself'; end if;
 if target_player=r.host_id then raise exception 'The host cannot be removed by a vote'; end if;
 if not exists(select 1 from public.room_members where room_id=target_room and user_id=target_player and not is_withdrawn) then raise exception 'Target player is not active'; end if;
 select count(*) into active_count from public.room_members where room_id=target_room and not is_withdrawn;
 if active_count<3 then raise exception 'At least three active players are required to start a vote'; end if;
 if exists(select 1 from public.scrabble_room_removal_votes where room_id=target_room and status='open') then raise exception 'A removal vote is already open'; end if;
 insert into public.scrabble_room_removal_votes(room_id,target_user_id,started_by) values(target_room,target_player,auth.uid()) returning id into vote_id;
 insert into public.scrabble_room_removal_ballots(vote_id,voter_id,approve) values(vote_id,auth.uid(),true);
 return vote_id;
end; $$;
revoke all on function public.start_scrabble_room_removal_vote(uuid,uuid) from public,anon;
grant execute on function public.start_scrabble_room_removal_vote(uuid,uuid) to authenticated;
create or replace function public.cast_scrabble_room_removal_vote(target_vote uuid,approve boolean)
returns text language plpgsql security definer set search_path=''
as $$ declare v public.scrabble_room_removal_votes; active_count integer; eligible_count integer; yes_count integer; no_count integer; ballot_count integer; begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into v from public.scrabble_room_removal_votes where id=target_vote for update;
 if not found or v.status<>'open' then raise exception 'Vote is no longer open'; end if;
 if not exists(select 1 from public.room_members where room_id=v.room_id and user_id=auth.uid() and not is_withdrawn) then raise exception 'Active room membership required'; end if;
 if auth.uid()=v.target_user_id then raise exception 'The target player cannot vote'; end if;
 select count(*) into active_count from public.room_members where room_id=v.room_id and not is_withdrawn;
 eligible_count:=active_count-1;
 if exists(select 1 from public.scrabble_room_removal_ballots where vote_id=target_vote and voter_id=auth.uid()) then raise exception 'You have already voted'; end if;
 insert into public.scrabble_room_removal_ballots(vote_id,voter_id,approve) values(target_vote,auth.uid(),approve);
 select count(*) filter(where b.approve),count(*) filter(where not b.approve),count(*) into yes_count,no_count,ballot_count
 from public.scrabble_room_removal_ballots b join public.room_members m on m.room_id=v.room_id and m.user_id=b.voter_id and not m.is_withdrawn where b.vote_id=target_vote;
 if yes_count>eligible_count/2 then
   update public.scrabble_room_removal_votes set status='approved',resolved_at=now() where id=target_vote;
   perform private.apply_scrabble_room_removal(v.room_id,v.target_user_id,'player_vote'); return 'approved';
 elsif no_count>eligible_count/2 or ballot_count>=eligible_count then
   update public.scrabble_room_removal_votes set status='rejected',resolved_at=now() where id=target_vote; return 'rejected';
 end if;
 return 'open';
end; $$;
revoke all on function public.cast_scrabble_room_removal_vote(uuid,boolean) from public,anon;
grant execute on function public.cast_scrabble_room_removal_vote(uuid,boolean) to authenticated;

do $$
begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='scrabble_room_removal_votes') then
   alter publication supabase_realtime add table public.scrabble_room_removal_votes;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='scrabble_room_removal_ballots') then
   alter publication supabase_realtime add table public.scrabble_room_removal_ballots;
 end if;
end $$;


-- Account-backed single-elimination tournaments.
create table if not exists public.scrabble_tournaments (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.profiles(id) on delete cascade,
 name text not null check(char_length(name) between 3 and 48),
 language text not null check(language in ('ar','en')),
 max_players integer not null check(max_players in (4,8,16)),
 status text not null default 'registration' check(status in ('registration','ongoing','completed','cancelled')),
 champion_id uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(), started_at timestamptz, completed_at timestamptz
);
create index if not exists scrabble_tournaments_status_created_idx on public.scrabble_tournaments(status,created_at desc);
create table if not exists public.scrabble_tournament_players (
 tournament_id uuid not null references public.scrabble_tournaments(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 joined_at timestamptz not null default now(), seed integer,
 primary key(tournament_id,user_id)
);
create table if not exists public.scrabble_tournament_matches (
 id uuid primary key default gen_random_uuid(),
 tournament_id uuid not null references public.scrabble_tournaments(id) on delete cascade,
 round_number integer not null check(round_number>0), match_number integer not null check(match_number>0),
 player1_id uuid references public.profiles(id) on delete set null,
 player2_id uuid references public.profiles(id) on delete set null,
 winner_id uuid references public.profiles(id) on delete set null,
 status text not null default 'scheduled' check(status in ('scheduled','completed')),
 created_at timestamptz not null default now(),
 unique(tournament_id,round_number,match_number),
 check(player1_id is null or player2_id is null or player1_id<>player2_id)
);
create index if not exists scrabble_tournament_players_user_idx on public.scrabble_tournament_players(user_id,tournament_id);
create index if not exists scrabble_tournament_matches_lookup_idx on public.scrabble_tournament_matches(tournament_id,round_number,match_number);
alter table public.scrabble_tournaments enable row level security;
alter table public.scrabble_tournament_players enable row level security;
alter table public.scrabble_tournament_matches enable row level security;
revoke all on public.scrabble_tournaments,public.scrabble_tournament_players,public.scrabble_tournament_matches from public,anon,authenticated;
grant select on public.scrabble_tournaments,public.scrabble_tournament_players,public.scrabble_tournament_matches to authenticated;
drop policy if exists "signed in users can read tournaments" on public.scrabble_tournaments;
create policy "signed in users can read tournaments" on public.scrabble_tournaments for select to authenticated using(true);
drop policy if exists "signed in users can read tournament players" on public.scrabble_tournament_players;
create policy "signed in users can read tournament players" on public.scrabble_tournament_players for select to authenticated using(true);
drop policy if exists "signed in users can read tournament matches" on public.scrabble_tournament_matches;
create policy "signed in users can read tournament matches" on public.scrabble_tournament_matches for select to authenticated using(true);

create or replace function public.create_scrabble_tournament(tournament_name text, game_language text, player_limit integer)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare uid uuid:=auth.uid(); tid uuid;
begin
 if uid is null then raise exception 'Sign in required'; end if;
 if char_length(trim(coalesce(tournament_name,''))) not between 3 and 48 then raise exception 'Tournament name must be 3 to 48 characters'; end if;
 if game_language not in ('ar','en') or player_limit not in (4,8,16) then raise exception 'Invalid tournament settings'; end if;
 insert into public.scrabble_tournaments(owner_id,name,language,max_players) values(uid,trim(tournament_name),game_language,player_limit) returning id into tid;
 insert into public.scrabble_tournament_players(tournament_id,user_id,seed) values(tid,uid,1);
 return tid;
end;
$function$;
create or replace function public.join_scrabble_tournament(target_tournament uuid)
returns void language plpgsql security definer set search_path=''
as $function$
declare uid uuid:=auth.uid(); target public.scrabble_tournaments; n integer;
begin
 if uid is null then raise exception 'Sign in required'; end if;
 select * into target from public.scrabble_tournaments where id=target_tournament for update;
 if not found or target.status<>'registration' then raise exception 'Registration is closed'; end if;
 if exists(select 1 from public.scrabble_tournament_players where tournament_id=target_tournament and user_id=uid) then return; end if;
 select count(*) into n from public.scrabble_tournament_players where tournament_id=target_tournament;
 if n>=target.max_players then raise exception 'Tournament is full'; end if;
 insert into public.scrabble_tournament_players(tournament_id,user_id,seed) values(target_tournament,uid,n+1);
end;
$function$;
create or replace function public.start_scrabble_tournament(target_tournament uuid)
returns void language plpgsql security definer set search_path=''
as $function$
declare target public.scrabble_tournaments; entrants uuid[]; n integer; i integer; round_size integer:=1; p1 uuid; p2 uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into target from public.scrabble_tournaments where id=target_tournament for update;
 if not found or target.owner_id<>auth.uid() then raise exception 'Only the tournament host can start it'; end if;
 if target.status<>'registration' then raise exception 'Tournament already started'; end if;
 select array_agg(user_id order by joined_at,user_id),count(*) into entrants,n from public.scrabble_tournament_players where tournament_id=target_tournament;
 if n<2 then raise exception 'At least two players are required'; end if;
 while round_size<n loop round_size:=round_size*2; end loop;
 for i in 1..(round_size/2) loop
  p1:=entrants[(i*2)-1]; p2:=entrants[i*2];
  if p1 is null and p2 is null then continue; end if;
  insert into public.scrabble_tournament_matches(tournament_id,round_number,match_number,player1_id,player2_id,winner_id,status)
  values(target_tournament,1,i,p1,p2,case when p1 is null or p2 is null then coalesce(p1,p2) else null end,case when p1 is null or p2 is null then 'completed' else 'scheduled' end);
 end loop;
 update public.scrabble_tournaments set status='ongoing',started_at=now() where id=target_tournament;
end;
$function$;
create or replace function public.report_scrabble_tournament_match(target_match uuid, winning_player uuid)
returns void language plpgsql security definer set search_path=''
as $function$
declare m public.scrabble_tournament_matches; t public.scrabble_tournaments; winners uuid[]; remaining integer; next_round integer; i integer; total_winners integer; p1 uuid; p2 uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into m from public.scrabble_tournament_matches where id=target_match for update;
 if not found then raise exception 'Match not found'; end if;
 select * into t from public.scrabble_tournaments where id=m.tournament_id for update;
 if t.owner_id<>auth.uid() then raise exception 'Only the tournament host can record results'; end if;
 if t.status<>'ongoing' or m.status<>'scheduled' then raise exception 'Match is not awaiting a result'; end if;
 if winning_player is null or (winning_player<>m.player1_id and winning_player<>m.player2_id) then raise exception 'Winner must be one of the match players'; end if;
 update public.scrabble_tournament_matches set winner_id=winning_player,status='completed' where id=target_match;
 select count(*) into remaining from public.scrabble_tournament_matches where tournament_id=m.tournament_id and round_number=m.round_number and status<>'completed';
 if remaining>0 then return; end if;
 select array_agg(winner_id order by match_number),count(*) into winners,total_winners from public.scrabble_tournament_matches where tournament_id=m.tournament_id and round_number=m.round_number and winner_id is not null;
 if total_winners=1 then
  update public.scrabble_tournaments set status='completed',champion_id=winners[1],completed_at=now() where id=m.tournament_id;
  return;
 end if;
 next_round:=m.round_number+1;
 for i in 1..((total_winners+1)/2) loop
  p1:=winners[(i*2)-1]; p2:=winners[i*2];
  insert into public.scrabble_tournament_matches(tournament_id,round_number,match_number,player1_id,player2_id,winner_id,status)
  values(m.tournament_id,next_round,i,p1,p2,case when p1 is null or p2 is null then coalesce(p1,p2) else null end,case when p1 is null or p2 is null then 'completed' else 'scheduled' end);
 end loop;
end;
$function$;
revoke all on function public.create_scrabble_tournament(text,text,integer) from public,anon;
revoke all on function public.join_scrabble_tournament(uuid) from public,anon;
revoke all on function public.start_scrabble_tournament(uuid) from public,anon;
revoke all on function public.report_scrabble_tournament_match(uuid,uuid) from public,anon;
grant execute on function public.create_scrabble_tournament(text,text,integer) to authenticated;
grant execute on function public.join_scrabble_tournament(uuid) to authenticated;
grant execute on function public.start_scrabble_tournament(uuid) to authenticated;
grant execute on function public.report_scrabble_tournament_match(uuid,uuid) to authenticated;


-- Tournament games are real two-player rooms. The database links the room result
-- to its bracket match and advances the bracket without host intervention.
alter table public.scrabble_tournament_matches
  add column if not exists room_id uuid unique references public.rooms(id) on delete set null;

alter table public.scrabble_tournament_matches
  drop constraint if exists scrabble_tournament_matches_status_check;
alter table public.scrabble_tournament_matches
  add constraint scrabble_tournament_matches_status_check
  check (status in ('scheduled','completed','tied'));

create or replace function public.complete_scrabble_tournament_match(target_match uuid, winning_player uuid)
returns void language plpgsql security definer set search_path=''
as $function$
declare m public.scrabble_tournament_matches; t public.scrabble_tournaments; winners uuid[]; pending integer; next_round integer; i integer; total_winners integer; p1 uuid; p2 uuid; current_round integer;
begin
 select * into m from public.scrabble_tournament_matches where id=target_match for update;
 if not found or m.status<>'scheduled' then return; end if;
 if winning_player is null or (winning_player<>m.player1_id and winning_player<>m.player2_id) then raise exception 'Verified winner must be a participant in this match'; end if;
 select * into t from public.scrabble_tournaments where id=m.tournament_id for update;
 if not found or t.status<>'ongoing' then return; end if;
 update public.scrabble_tournament_matches set winner_id=winning_player,status='completed' where id=target_match;
 current_round:=m.round_number;
 loop
  select count(*) into pending from public.scrabble_tournament_matches where tournament_id=m.tournament_id and round_number=current_round and status<>'completed';
  if pending>0 then exit; end if;
  select array_agg(winner_id order by match_number),count(*) into winners,total_winners from public.scrabble_tournament_matches where tournament_id=m.tournament_id and round_number=current_round and status='completed' and winner_id is not null;
  if total_winners=1 then
   update public.scrabble_tournaments set status='completed',champion_id=winners[1],completed_at=now() where id=m.tournament_id;
   exit;
  end if;
  if coalesce(total_winners,0)<2 then raise exception 'Tournament bracket has no valid advancing players'; end if;
  next_round:=current_round+1;
  for i in 1..((total_winners+1)/2) loop
   p1:=winners[(i*2)-1]; p2:=winners[i*2];
   insert into public.scrabble_tournament_matches(tournament_id,round_number,match_number,player1_id,player2_id,winner_id,status)
   values(m.tournament_id,next_round,i,p1,p2,case when p2 is null then p1 else null end,case when p2 is null then 'completed' else 'scheduled' end);
  end loop;
  current_round:=next_round;
 end loop;
end;
$function$;
revoke all on function public.complete_scrabble_tournament_match(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.create_scrabble_tournament_match_room(target_match uuid)
returns public.rooms language plpgsql security definer set search_path=''
as $function$
declare uid uuid:=auth.uid(); m public.scrabble_tournament_matches; t public.scrabble_tournaments; created public.rooms;
begin
 if uid is null then raise exception 'Sign in required'; end if;
 select * into m from public.scrabble_tournament_matches where id=target_match for update;
 if not found then raise exception 'Tournament match not found'; end if;
 if uid<>m.player1_id and uid<>m.player2_id then raise exception 'Only match participants can open this game'; end if;
 select * into t from public.scrabble_tournaments where id=m.tournament_id for update;
 if not found or t.status<>'ongoing' then raise exception 'Tournament is not active'; end if;
 if m.status not in ('scheduled','tied') then raise exception 'Tournament match is already completed'; end if;
 if m.room_id is not null then
  select * into created from public.rooms where id=m.room_id;
  if found and created.status in ('waiting','playing') then return created; end if;
 end if;
 insert into public.rooms(name,host_id,is_public,max_players,language)
 values(left(t.name||' · R'||m.round_number||' M'||m.match_number,40),uid,false,2,t.language)
 returning * into created;
 insert into public.room_members(room_id,user_id,seat) values(created.id,m.player1_id,1),(created.id,m.player2_id,2);
 update public.scrabble_tournament_matches set room_id=created.id,status='scheduled',winner_id=null where id=target_match;
 return created;
end;
$function$;
revoke all on function public.create_scrabble_tournament_match_room(uuid) from public,anon;
grant execute on function public.create_scrabble_tournament_match_room(uuid) to authenticated;

create or replace function public.sync_scrabble_tournament_match_result()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare m public.scrabble_tournament_matches; best_score integer; best_count integer; winning_player uuid;
begin
 if old.status<>'playing' or new.status<>'finished' then return new; end if;
 select * into m from public.scrabble_tournament_matches where room_id=new.id and status='scheduled' for update;
 if not found then return new; end if;
 select max(score),count(*) filter(where score=(select max(score) from public.scrabble_match_results where room_id=new.id))
 into best_score,best_count from public.scrabble_match_results where room_id=new.id;
 if best_score is null or best_count=0 then raise exception 'Verified match result is missing; tournament cannot advance'; end if;
 if best_count>1 then
  update public.scrabble_tournament_matches set status='tied',room_id=null,winner_id=null where id=m.id;
  return new;
 end if;
 select user_id into winning_player from public.scrabble_match_results where room_id=new.id and score=best_score order by created_at asc limit 1;
 perform public.complete_scrabble_tournament_match(m.id,winning_player);
 return new;
end;
$function$;
revoke all on function public.sync_scrabble_tournament_match_result() from public,anon,authenticated,service_role;
drop trigger if exists zz_sync_scrabble_tournament_match_result on public.rooms;
create trigger zz_sync_scrabble_tournament_match_result after update of status on public.rooms
for each row when(old.status='playing' and new.status='finished')
execute function public.sync_scrabble_tournament_match_result();
drop function if exists public.report_scrabble_tournament_match(uuid,uuid);

do $$
begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='scrabble_tournament_matches') then
  alter publication supabase_realtime add table public.scrabble_tournament_matches;
 end if;
end $$;


-- Tournament scheduling, virtual rewards, and safe read-only spectating.
alter table public.scrabble_tournaments
  add column if not exists scheduled_at timestamptz,
  add column if not exists prize_xp integer not null default 0,
  add column if not exists prize_coins integer not null default 0,
  add column if not exists spectators_enabled boolean not null default true,
  add column if not exists prize_awarded_at timestamptz;
alter table public.scrabble_tournaments
  drop constraint if exists scrabble_tournaments_prize_xp_check,
  drop constraint if exists scrabble_tournaments_prize_coins_check;
alter table public.scrabble_tournaments
  add constraint scrabble_tournaments_prize_xp_check check(prize_xp between 0 and 100000),
  add constraint scrabble_tournaments_prize_coins_check check(prize_coins between 0 and 100000);
create or replace function public.set_scrabble_tournament_details(target_tournament uuid, starts_at timestamptz, reward_xp integer, reward_coins integer, allow_spectators boolean)
returns void language plpgsql security definer set search_path=''
as $function$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if reward_xp not between 0 and 100000 or reward_coins not between 0 and 100000 then raise exception 'Tournament rewards are out of range'; end if;
 update public.scrabble_tournaments set scheduled_at=starts_at,prize_xp=reward_xp,prize_coins=reward_coins,spectators_enabled=coalesce(allow_spectators,true)
 where id=target_tournament and owner_id=auth.uid() and status='registration';
 if not found then raise exception 'Only the tournament host can edit an open tournament'; end if;
end;
$function$;
revoke all on function public.set_scrabble_tournament_details(uuid,timestamptz,integer,integer,boolean) from public,anon;
grant execute on function public.set_scrabble_tournament_details(uuid,timestamptz,integer,integer,boolean) to authenticated;
create or replace function public.get_scrabble_tournament_spectator_state(target_match uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare m public.scrabble_tournament_matches; t public.scrabble_tournaments; r public.rooms;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into m from public.scrabble_tournament_matches where id=target_match;
 if not found then raise exception 'Tournament match not found'; end if;
 select * into t from public.scrabble_tournaments where id=m.tournament_id;
 if not found or not t.spectators_enabled then raise exception 'Spectating is disabled for this tournament'; end if;
 if m.room_id is null then raise exception 'This match has not started yet'; end if;
 select * into r from public.rooms where id=m.room_id;
 if not found or r.status not in ('playing','finished') then raise exception 'This match is not available to watch'; end if;
 return jsonb_build_object('match_id',m.id,'tournament_id',t.id,'tournament_name',t.name,'round_number',m.round_number,'match_number',m.match_number,
 'player1_id',m.player1_id,'player2_id',m.player2_id,'room_status',r.status,'language',t.language,
 'game_state',jsonb_build_object('board',coalesce(r.game_state->'board','[]'::jsonb),'player_ids',coalesce(r.game_state->'player_ids','[]'::jsonb),
 'scores',coalesce(r.game_state->'scores','[]'::jsonb),'turn_index',coalesce(r.game_state->'turn_index','0'::jsonb),
 'bag_count',coalesce(r.game_state->'bag_count','0'::jsonb),'revision',coalesce(r.game_state->'revision','0'::jsonb),'history',coalesce(r.game_state->'history','[]'::jsonb)));
end;
$function$;
revoke all on function public.get_scrabble_tournament_spectator_state(uuid) from public,anon;
grant execute on function public.get_scrabble_tournament_spectator_state(uuid) to authenticated;
create or replace function public.award_scrabble_tournament_prize()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
 if old.status<>'completed' and new.status='completed' and new.champion_id is not null and new.prize_awarded_at is null then
  update public.profiles set xp=xp+new.prize_xp,updated_at=now() where id=new.champion_id and new.prize_xp>0;
  insert into public.scrabble_wallets(user_id,coins,updated_at) values(new.champion_id,new.prize_coins,now())
  on conflict(user_id) do update set coins=public.scrabble_wallets.coins+excluded.coins,updated_at=now();
  update public.scrabble_tournaments set prize_awarded_at=now() where id=new.id;
 end if;
 return new;
end;
$function$;
revoke all on function public.award_scrabble_tournament_prize() from public,anon,authenticated,service_role;
drop trigger if exists award_scrabble_tournament_prize on public.scrabble_tournaments;
create trigger award_scrabble_tournament_prize after update of status on public.scrabble_tournaments
for each row when(old.status<>'completed' and new.status='completed') execute function public.award_scrabble_tournament_prize();
