
-- Cache auth.uid() once per statement in room RLS checks.
create or replace function public.is_scrabble_room_member(target_room uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists(
    select 1 from public.room_members
    where room_id=target_room and user_id=(select auth.uid())
  )
$function$;

drop policy if exists "rooms visible to members or public waiting rooms" on public.rooms;
create policy "rooms visible to members or public waiting rooms"
on public.rooms for select to authenticated
using (
  (is_public and status='waiting')
  or public.is_scrabble_room_member(id)
  or exists(
    select 1 from public.room_invites ri
    where ri.room_id=rooms.id
      and ri.receiver_id=(select auth.uid())
      and ri.status in ('pending','accepted')
  )
);

drop policy if exists "send room invites" on public.room_invites;
create policy "send room invites"
on public.room_invites for insert to authenticated
with check (
  sender_id=(select auth.uid())
  and public.is_scrabble_room_member(room_id)
  and exists(
    select 1 from public.friendships f
    where (f.user_low=(select auth.uid()) and f.user_high=room_invites.receiver_id)
       or (f.user_high=(select auth.uid()) and f.user_low=room_invites.receiver_id)
  )
);

drop policy if exists "receiver updates room invite" on public.room_invites;
create policy "receiver updates room invite"
on public.room_invites for update to authenticated
using (receiver_id=(select auth.uid()) and status='pending')
with check (receiver_id=(select auth.uid()) and status in ('accepted','rejected'));

revoke all on function public.is_scrabble_room_member(uuid) from public, anon;
grant execute on function public.is_scrabble_room_member(uuid) to authenticated;
