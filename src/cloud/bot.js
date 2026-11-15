import { isCloudConfigured, supabase } from './supabase.js';

export async function requestBotWords(session) {
  if (!isCloudConfigured || !supabase || !session?.players?.[session.currentPlayer]) return [];
  const { data: authData } = await supabase.auth.getSession();
  if (!authData?.session?.access_token) return [];
  const player = session.players[session.currentPlayer];
  const { data, error } = await supabase.functions.invoke('scrabble-bot', {
    body: {
      language: session.language,
      rack: player.rack.map(tile => ({ letter: tile.letter, isBlank: Boolean(tile.isBlank) })),
      board: session.board.map(tile => tile ? { letter: tile.letter, blankAs: tile.blankAs || null } : null),
    },
  });
  if (error) throw error;
  return Array.isArray(data?.words) ? data.words : [];
}
