-- Keep the unused client-state submission RPC disabled; live multiplayer
-- moves are validated by the authenticated scrabble-move Edge Function.
revoke all on function public.submit_scrabble_turn(uuid, integer, jsonb, jsonb) from public, anon, authenticated;
