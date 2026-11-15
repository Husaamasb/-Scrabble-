REVOKE ALL ON TABLE public.scrabble_saved_games FROM PUBLIC, anon;
GRANT SELECT,INSERT,UPDATE,DELETE ON TABLE public.scrabble_saved_games TO authenticated;
