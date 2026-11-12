import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateMove, applyMove, PREMIUM } from '../src/game/engine.js';
import { validateWords } from '../src/game/wordValidator.js';

const tile=(letter,points=1)=>({letter,points});

test('board has 225 squares, centered start, and symmetric premium squares',()=>{
  assert.equal(PREMIUM.length,225);
  assert.equal(PREMIUM[112],'DW');
  assert.equal(PREMIUM.filter(x=>x==='TW').length,8);
  assert.equal(PREMIUM.filter(x=>x==='DW').length,17);
  assert.equal(PREMIUM.filter(x=>x==='TL').length,12);
  assert.equal(PREMIUM.filter(x=>x==='DL').length,24);
  for(let r=0;r<15;r++)for(let c=0;c<15;c++)assert.equal(PREMIUM[r*15+c],PREMIUM[(14-r)*15+(14-c)]);
});

test('first move must cover center and make a word',()=>{
  assert.equal(evaluateMove({},[{row:7,col:6,tile:tile('C')},{row:7,col:7,tile:tile('A')},{row:7,col:8,tile:tile('T')}]).valid,true);
  assert.equal(evaluateMove({},[{row:0,col:0,tile:tile('A')}]).reason,'must-cover-center');
});

test('move rejects gaps and placements on occupied squares',()=>{
  assert.equal(evaluateMove({},[{row:7,col:6,tile:tile('C')},{row:7,col:8,tile:tile('T')}]).reason,'must-cover-center');
  const base={112:tile('A')};
  assert.equal(evaluateMove(base,[{row:7,col:7,tile:tile('T')}]).reason,'occupied-square');
});

test('center double-word multiplier is applied on first placement',()=>{
  const move=applyMove({},[{row:7,col:6,tile:tile('C',3)},{row:7,col:7,tile:tile('A',1)},{row:7,col:8,tile:tile('T',1)}]);
  assert.equal(move.valid,true);
  assert.equal(move.total,10);
  assert.ok(move.board[112]);
});

test('later moves must connect to existing tiles',()=>{
  const base={112:tile('A')};
  assert.equal(evaluateMove(base,[{row:0,col:0,tile:tile('B')},{row:0,col:1,tile:tile('E')}]).reason,'not-connected');
});

test('dictionary adapter fails closed when no AI dictionary is configured',async()=>{
  assert.equal((await validateWords([{letters:'CAT'}],'en')).reason,'dictionary-service-not-configured');
  assert.equal((await validateWords([{letters:'CAT'}],'en',async()=>true)).valid,true);
});
