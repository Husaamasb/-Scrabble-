-- Persist the room owner's match-end choice. Turn timers remain disabled.
alter table public.rooms
  add column if not exists end_condition text not null default 'classic'
  check (end_condition in ('classic','bag_empty'));

create or replace function public.create_scrabble_room_with_rules(
  room_name text, public_room boolean, player_limit int, game_language text, match_end_mode text
)
returns setof public.rooms language plpgsql security definer set search_path = public
as $$
declare created public.rooms;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if player_limit not between 2 and 4 then raise exception 'Player limit must be 2 to 4'; end if;
  if match_end_mode not in ('classic','bag_empty') then raise exception 'Invalid match end condition'; end if;
  if game_language not in ('ar','en') then raise exception 'Invalid game language'; end if;
  insert into public.rooms(name,host_id,is_public,max_players,language,end_condition)
  values(left(room_name,40),auth.uid(),public_room,player_limit,game_language,match_end_mode)
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
grant execute on function public.create_scrabble_room_with_rules(text,boolean,int,text,text) to authenticated;

-- Enable realtime replication for the tables used by the app.
do $$
begin
  alter publication supabase_realtime add table public.room_messages;
exception when duplicate_object then null;
end $$;

grant execute on function public.create_scrabble_room_with_rules(text,boolean,int,text,text) to authenticated;

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
  if (select count(*) from public.room_tile_bag where room_id=target_room)=0 then
    if target.end_condition='bag_empty' then
      return public.settle_scrabble_room(target_room,null,'bag_empty');
    elsif jsonb_array_length(rack_next)=0 then
      return public.settle_scrabble_room(target_room,actor,'tiles_exhausted');
    end if;
  end if;
  return target;
end;
$function$
;

revoke all on function public.place_scrabble_word(uuid,integer,jsonb,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.place_scrabble_word(uuid,integer,jsonb,jsonb,uuid) to service_role;
