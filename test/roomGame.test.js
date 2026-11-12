import test from 'node:test';
import assert from 'node:assert/strict';
import { assertPublicGameState } from '../src/cloud/publicState.js';

test('public game state accepts visible board data', () => {
  const state = { board: { '112': { letter: 'A', points: 1 } }, scores: [10, 5], turn_index: 1 };
  assert.equal(assertPublicGameState(state), state);
});

test('public game state rejects hidden rack and bag fields', () => {
  assert.throws(() => assertPublicGameState({ board: {}, rack: ['A'] }), /Hidden tile data/);
  assert.throws(() => assertPublicGameState({ board: {}, player: { rack: ['A'] } }), /Hidden tile data/);
  assert.throws(() => assertPublicGameState({ board: {}, bag: [] }), /Hidden tile data/);
});
