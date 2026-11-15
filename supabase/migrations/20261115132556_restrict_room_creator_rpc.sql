-- Room creation functions are SECURITY DEFINER and must not be callable by anon/PUBLIC.
revoke all on function public.create_scrabble_room(text,boolean,integer,text) from public, anon;
grant execute on function public.create_scrabble_room(text,boolean,integer,text) to authenticated;

revoke all on function public.create_scrabble_room_with_rules(text,boolean,integer,text,text) from public, anon;
grant execute on function public.create_scrabble_room_with_rules(text,boolean,integer,text,text) to authenticated;
