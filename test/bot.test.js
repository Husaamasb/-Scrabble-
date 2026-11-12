import test from 'node:test';
import assert from 'node:assert/strict';
import { orderBotMoves } from '../src/game/bot.js';

const moves=Array.from({length:20},(_,i)=>({points:200-i}));

test('all bot levels keep every candidate available as a fallback',()=>{
  for(let level=1;level<=5;level++){
    const ordered=orderBotMoves(moves,level,()=>0.42);
    assert.equal(ordered.length,moves.length);
    assert.deepEqual(new Set(ordered),new Set(moves));
  }
});

test('hardest level only explores the strongest score group first',()=>{
  const ordered=orderBotMoves(moves,5,()=>0.5);
  assert.ok(ordered.slice(0,2).every(move=>move.points>=198));
  assert.ok(ordered.slice(2).some(move=>move.points<198));
});

test('easiest level can choose from the full candidate set',()=>{
  const ordered=orderBotMoves(moves,1,()=>0.5);
  assert.equal(ordered.length,20);
  assert.notEqual(ordered[0],moves[0]);
});

test('invalid levels are safely clamped',()=>{
  assert.deepEqual(orderBotMoves(moves,99,()=>0),orderBotMoves(moves,5,()=>0));
});
