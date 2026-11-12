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

test('blank tile stays worth zero even when placed on a word premium',()=>{
  const move=evaluateMove({},[
    {row:7,col:6,tile:{letter:'?',blankAs:'C',points:0,isBlank:true}},
    {row:7,col:7,tile:tile('A',1)},
    {row:7,col:8,tile:tile('T',1)}
  ]);
  assert.equal(move.valid,true);
  assert.equal(move.words[0].letters,'CAT');
  assert.equal(move.total,4);
});

test('using all seven tiles earns the 50 point bonus',()=>{
  const placements=Array.from({length:7},(_,i)=>({row:7,col:4+i,tile:tile('A',1)}));
  const move=evaluateMove({},placements);
  assert.equal(move.valid,true);
  assert.equal(move.bingo,50);
  assert.equal(move.total,64);
});

test('a premium square is not reused after its first placement',()=>{
  const board={112:tile('A',1)};
  const move=evaluateMove(board,[{row:7,col:8,tile:tile('T',1)}]);
  assert.equal(move.valid,true);
  assert.equal(move.total,2);
});

test('blank tile remains zero points even on a triple-letter square',()=>{
  const board={19:tile('A',1)};
  const move=evaluateMove(board,[{row:1,col:5,tile:{letter:'X',points:8,isBlank:true}}]);
  assert.equal(move.valid,true);
  assert.equal(move.total,1);
});

test('one new tile scores every cross-word it creates',()=>{
  const board={97:tile('A',1),127:tile('T',1),111:tile('I',1)};
  const move=evaluateMove(board,[{row:7,col:7,tile:tile('C',3)}]);
  assert.equal(move.valid,true);
  assert.equal(move.words.length,2);
  assert.equal(move.total,18);
});

test('custom premium layouts override the standard square multipliers',()=>{
  const custom=Array(225).fill(null);custom[112]='TW';
  const move=evaluateMove({},[{row:7,col:6,tile:tile('C',3)},{row:7,col:7,tile:tile('A',1)},{row:7,col:8,tile:tile('T',1)}],custom);
  assert.equal(move.valid,true);
  assert.equal(move.total,15);
});
