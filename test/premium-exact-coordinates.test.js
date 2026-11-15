import test from 'node:test';
import assert from 'node:assert/strict';
import { PREMIUM } from '../src/game/engine.js';

const indices = pairs => pairs.map(([r,c]) => r*15+c).sort((a,b)=>a-b);
const actual = kind => PREMIUM.flatMap((value,index)=>value===kind?[index]:[]).sort((a,b)=>a-b);

test('all triple-word coordinates are fixed to the specification',()=>{
  assert.deepEqual(actual('TW'),indices([[0,0],[0,7],[0,14],[7,0],[7,14],[14,0],[14,7],[14,14]]));
});
test('all triple-letter coordinates are fixed to the specification',()=>{
  assert.deepEqual(actual('TL'),indices([[1,5],[1,9],[5,1],[5,5],[5,9],[5,13],[9,1],[9,5],[9,9],[9,13],[13,5],[13,9]]));
});
test('all double-letter coordinates are fixed to the specification',()=>{
  assert.deepEqual(actual('DL'),indices([[0,3],[0,11],[2,6],[2,8],[3,0],[3,7],[3,14],[6,2],[6,6],[6,8],[6,12],[7,3],[7,11],[8,2],[8,6],[8,8],[8,12],[11,0],[11,7],[11,14],[12,6],[12,8],[14,3],[14,11]]));
});
