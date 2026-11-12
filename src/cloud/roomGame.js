import { supabase } from './supabase.js';

const HIDDEN_KEYS = new Set(['rack','racks','bag','tiles','private_state']);

export function assertPublicGameState(state) {
  if (!state || typeof state !== 'object' || Array.isArray(state)) {
    throw new Error('Invalid public game state');
  }
  for (const key of Object.keys(state)) {
    if (HIDDEN_KEYS.has(key)) throw new Error('Hidden tile data cannot be published');
  }
  return state;
}

export async function loadRoomPlayerState(roomId) {
  const { data, error } = await supabase
    .from('room_player_private')
    .select('private_state,updated_at')
    .eq('room_id', roomId)
    .maybeSingle();
  if (error) throw error;
  return data?.private_state ?? null;
}

export async function publishRoomTurn({ roomId, expectedRevision, publicState, privateState }) {
  assertPublicGameState(publicState);
  if (!privateState || typeof privateState !== 'object' || Array.isArray(privateState)) {
    throw new Error('Invalid private player state');
  }
  const { data, error } = await supabase.rpc('submit_scrabble_turn', {
    target_room: roomId,
    expected_revision: expectedRevision,
    public_state: publicState,
    private_state: privateState
  });
  if (error) throw error;
  return data;
}

export function subscribeRoomGame(roomId, onChange) {
  const channel = supabase
    .channel('scrabble-game:' + roomId)
    .on('postgres_changes', {
      event: 'UPDATE',
      schema: 'public',
      table: 'rooms',
      filter: 'id=eq.' + roomId
    }, payload => onChange(payload.new))
    .subscribe();
  return () => supabase.removeChannel(channel);
}
