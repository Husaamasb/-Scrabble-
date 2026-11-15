-- Allow signed-in room members to submit validated turns.
-- The function checks auth.uid(), room membership, turn ownership, and revision.
revoke all on function public.submit_scrabble_turn(uuid, integer, jsonb, jsonb) from public, anon;
grant execute on function public.submit_scrabble_turn(uuid, integer, jsonb, jsonb) to authenticated;
