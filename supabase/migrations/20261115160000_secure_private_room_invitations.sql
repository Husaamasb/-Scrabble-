-- Harden private-room invitations and preserve invited-room visibility.
create or replace function public.join_room_by_code(room_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.rooms;
  next_seat int;
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Sign in required';
  end if;

  select * into target
  from public.rooms
  where code = room_code and status = 'waiting'
  for update;

  if not found then
    raise exception 'Room not found or already started';
  end if;

  if exists (
    select 1 from public.room_members
    where room_id = target.id and user_id = uid
  ) then
    return target.id;
  end if;

  if not target.is_public and not exists (
    select 1 from public.room_invites
    where room_id = target.id
      and receiver_id = uid
      and status = 'accepted'
  ) then
    raise exception 'An accepted room invitation is required';
  end if;

  select coalesce(max(seat), 0) + 1 into next_seat
  from public.room_members
  where room_id = target.id;

  if next_seat > target.max_players then
    raise exception 'Room is full';
  end if;

  insert into public.room_members(room_id, user_id, seat)
  values (target.id, uid, next_seat);

  return target.id;
end;
$$;

drop policy if exists "rooms visible to members or public waiting rooms" on public.rooms;
create policy "rooms visible to members or public waiting rooms"
on public.rooms
for select
to authenticated
using (
  (is_public and status = 'waiting')
  or public.is_scrabble_room_member(id)
  or exists (
    select 1
    from public.room_invites ri
    where ri.room_id = rooms.id
      and ri.receiver_id = auth.uid()
      and ri.status in ('pending', 'accepted')
  )
);

drop policy if exists "send room invites" on public.room_invites;
create policy "send room invites"
on public.room_invites
for insert
to authenticated
with check (
  sender_id = auth.uid()
  and public.is_scrabble_room_member(room_id)
  and exists (
    select 1
    from public.friendships f
    where (f.user_low = auth.uid() and f.user_high = receiver_id)
       or (f.user_high = auth.uid() and f.user_low = receiver_id)
  )
);

revoke update on public.room_invites from authenticated;
grant update(status) on public.room_invites to authenticated;

drop policy if exists "receiver updates room invite" on public.room_invites;
create policy "receiver updates room invite"
on public.room_invites
for update
to authenticated
using (receiver_id = auth.uid() and status = 'pending')
with check (receiver_id = auth.uid() and status in ('accepted', 'rejected'));

create unique index if not exists one_pending_room_invite_per_recipient
on public.room_invites(room_id, receiver_id)
where status = 'pending';

grant execute on function public.join_room_by_code(text) to authenticated;
