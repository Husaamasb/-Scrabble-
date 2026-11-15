-- Cache auth.uid() once per statement in row-level security policies.
alter policy "players update own heartbeat" on public.room_members
  using (
    user_id = (select auth.uid())
    and not is_withdrawn
    and exists (
      select 1 from public.rooms r
      where r.id = room_members.room_id and r.status = 'playing'
    )
  )
  with check (
    user_id = (select auth.uid())
    and not is_withdrawn
    and last_seen_at <= (clock_timestamp() + interval '10 seconds')
    and exists (
      select 1 from public.rooms r
      where r.id = room_members.room_id and r.status = 'playing'
    )
  );

alter policy "players create own reports" on public.scrabble_player_reports
  with check (reporter_id = (select auth.uid()));

alter policy "players read own reports and admins read all" on public.scrabble_player_reports
  using (reporter_id = (select auth.uid()) or public.is_scrabble_admin());

alter policy "admins manage dictionary overrides" on public.scrabble_dictionary_overrides
  using (public.is_scrabble_admin())
  with check (
    public.is_scrabble_admin()
    and updated_by = (select auth.uid())
  );

alter policy "tournament hosts update schedule" on public.scrabble_tournaments
  using (owner_id = (select auth.uid()) and status = 'registration')
  with check (owner_id = (select auth.uid()) and status = 'registration');
