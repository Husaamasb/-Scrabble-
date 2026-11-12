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
  premium_layout jsonb,
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
drop policy if exists "host updates room" on public.rooms;
create policy "host updates room" on public.rooms for update to authenticated using(host_id=auth.uid()) with check(host_id=auth.uid());

drop policy if exists "members see room members" on public.room_members;
create policy "members see room members" on public.room_members for select to authenticated using(public.is_scrabble_room_member(room_id));
drop policy if exists "join own room membership" on public.room_members;
drop policy if exists "users update own membership" on public.room_members;
create policy "users update own membership" on public.room_members for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists "users leave own room" on public.room_members;
create policy "users leave own room" on public.room_members for delete to authenticated using(user_id=auth.uid());

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
  update public.room_members set is_ready=ready_state where room_id=target_room and user_id=auth.uid();
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
