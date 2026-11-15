import test from 'node:test';
import assert from 'node:assert/strict';
import { PREMIUM } from '../src/game/engine.js';

const indexes = pairs => pairs.map(([r,c]) => r * 15 + c);

test('double-word squares match every owner-approved coordinate exactly', () => {
  const expected = indexes([
    [1,3],[1,11],[2,2],[2,12],[3,1],[3,13],[4,4],[4,10],[7,7],
    [10,4],[10,10],[11,1],[11,13],[12,2],[12,12],[13,3],[13,11]
  ]).sort((a,b)=>a-b);
  const actual = PREMIUM.flatMap((value,index)=>value==='DW'?[index]:[]).sort((a,b)=>a-b);
  assert.deepEqual(actual, expected);
});

test('three-word, triple-letter and double-letter squares retain their exact counts', () => {
  assert.equal(PREMIUM.filter(value=>value==='TW').length,8);
  assert.equal(PREMIUM.filter(value=>value==='TL').length,12);
  assert.equal(PREMIUM.filter(value=>value==='DL').length,24);
});
