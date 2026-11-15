-- Publish room invitations so recipients receive live invite updates.
do $$
begin
  alter publication supabase_realtime add table public.room_invites;
exception when duplicate_object then
  null;
end $$;
