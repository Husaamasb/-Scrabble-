
-- Allow the room host to start a fresh rematch with the same active players and rules.
create or replace function public.rematch_scrabble_room(target_room uuid)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $function$
declare
  previous public.rooms;
  created public.rooms;
  copied_members integer;
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  select * into previous
  from public.rooms
  where id = target_room
  for update;

  if not found or previous.status <> 'finished' then
    raise exception 'Only a finished room can be rematched';
  end if;

  if previous.host_id <> auth.uid() then
    raise exception 'Only the room host can start a rematch';
  end if;

  if not exists (
    select 1 from public.room_members
    where room_id = target_room
      and user_id = auth.uid()
      and not is_withdrawn
  ) then
    raise exception 'The host must still be an active room member';
  end if;

  insert into public.rooms
    (name, host_id, is_public, max_players, end_condition, language)
  values
    (left(previous.name || ' · إعادة', 40), auth.uid(), previous.is_public,
     previous.max_players, previous.end_condition, previous.language)
  returning * into created;

  insert into public.room_members(room_id, user_id, seat)
  select created.id, user_id,
         row_number() over(order by seat)::integer
  from public.room_members
  where room_id = target_room and not is_withdrawn
  order by seat;

  get diagnostics copied_members = row_count;
  if copied_members < 2 then
    raise exception 'At least two active players are required for a rematch';
  end if;

  return created;
end;
$function$;

revoke all on function public.rematch_scrabble_room(uuid) from public, anon;
grant execute on function public.rematch_scrabble_room(uuid) to authenticated;
