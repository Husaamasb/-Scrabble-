-- Combine admin access into existing policies to avoid duplicate permissive policies.
alter policy "profiles readable by privacy settings" on public.profiles
  using (
    id = (select auth.uid())
    or privacy = 'everyone'
    or (
      privacy = 'friends'
      and exists (
        select 1 from public.friendships f
        where
          (f.user_low = (select auth.uid()) and f.user_high = profiles.id)
          or
          (f.user_high = (select auth.uid()) and f.user_low = profiles.id)
      )
    )
    or public.is_scrabble_admin()
  );
drop policy "scrabble admins can read all profiles" on public.profiles;

alter policy "members see room members" on public.room_members
  using (public.is_scrabble_room_member(room_id) or public.is_scrabble_admin());
drop policy "scrabble admins can read all room members" on public.room_members;

alter policy "rooms visible to members or public waiting rooms" on public.rooms
  using (
    (is_public and status = 'waiting')
    or public.is_scrabble_room_member(id)
    or public.is_scrabble_admin()
  );
drop policy "scrabble admins can read all rooms" on public.rooms;

alter policy "tournament hosts update schedule" on public.scrabble_tournaments
  using (
    (owner_id = (select auth.uid()) or public.is_scrabble_admin())
    and status = 'registration'
  )
  with check (
    (owner_id = (select auth.uid()) or public.is_scrabble_admin())
    and status = 'registration'
  );
drop policy "admins update tournament details" on public.scrabble_tournaments;
