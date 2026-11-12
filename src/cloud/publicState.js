const HIDDEN_KEYS = new Set(['rack','racks','bag','tiles','private_state']);

export function assertPublicGameState(state) {
  if (!state || typeof state !== 'object' || Array.isArray(state)) {
    throw new Error('Invalid public game state');
  }
  const inspect = value => {
    if (Array.isArray(value)) {
      value.forEach(inspect);
      return;
    }
    if (!value || typeof value !== 'object') return;
    for (const [key, nested] of Object.entries(value)) {
      if (HIDDEN_KEYS.has(key)) throw new Error('Hidden tile data cannot be published');
      inspect(nested);
    }
  };
  inspect(state);
  return state;
}
