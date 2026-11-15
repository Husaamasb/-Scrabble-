create or replace function public.start_scrabble_room(target_room uuid)
 RETURNS public.rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
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
      ('ا',1,8),
      ('أ',1,2),
      ('إ',1,2),
      ('آ',8,1),
      ('ب',1,4),
      ('ت',1,4),
      ('ة',5,1),
      ('ث',1,3),
      ('ج',1,3),
      ('ح',1,3),
      ('خ',1,3),
      ('د',1,3),
      ('ذ',1,3),
      ('ر',2,3),
      ('ز',2,3),
      ('س',1,3),
      ('ش',2,3),
      ('ص',2,3),
      ('ض',3,3),
      ('ط',2,2),
      ('ظ',4,2),
      ('ع',2,3),
      ('غ',4,3),
      ('ف',1,3),
      ('ق',2,3),
      ('ك',3,3),
      ('ل',1,3),
      ('لا',2,2),
      ('لأ',3,1),
      ('لآ',3,1),
      ('لإ',3,1),
      ('م',1,4),
      ('ن',1,3),
      ('ه',1,3),
      ('و',1,3),
      ('ؤ',10,1),
      ('ي',1,3),
      ('ى',3,1),
      ('ء',8,1),
      ('ئ أول الكلمة',10,2),
      ('★',0,2)
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
$function$;