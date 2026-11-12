import test from 'node:test';
import assert from 'node:assert/strict';
import { commitTurn, exchangeFromRack, passTurn } from '../src/game/session.js';

const tile=(id,letter,points)=>({id,letter,points});
function sampleSession(){
  return {
    language:'en',
    players:[
      {id:'p1',name:'One',score:0,rack:[tile('c','C',3),tile('a','A',1),tile('t','T',1),tile('x','X',8),tile('e','E',1),tile('r','R',1),tile('s','S',1)]},
      {id:'p2',name:'Two',score:0,rack:[tile('b','B',3),tile('d','D',2)]}
    ],
    board:{},bag:Array.from({length:20},(_,i)=>({letter:'E',points:1})),
    currentPlayer:0,consecutivePasses:0,status:'playing',winner:null,history:[]
  };
}

test('turn commit requires a configured dictionary and does not mutate the source session',async()=>{
  const session=sampleSession();
  const result=await commitTurn(session,[{row:7,col:6,tile:session.players[0].rack[0]},{row:7,col:7,tile:session.players[0].rack[1]},{row:7,col:8,tile:session.players[0].rack[2]}]);
  assert.equal(result.ok,false);
  assert.equal(result.reason,'dictionary-service-not-configured');
  assert.equal(session.players[0].score,0);
  assert.equal(Object.keys(session.board).length,0);
});

test('valid dictionary approval commits score, board, rack refill, and next turn',async()=>{
  const session=sampleSession();
  const result=await commitTurn(session,[{row:7,col:6,tile:session.players[0].rack[0]},{row:7,col:7,tile:session.players[0].rack[1]},{row:7,col:8,tile:session.players[0].rack[2]}],async()=>true);
  assert.equal(result.ok,true);
  assert.equal(result.move.total,10);
  assert.equal(result.session.players[0].score,10);
  assert.equal(result.session.players[0].rack.length,7);
  assert.equal(result.session.currentPlayer,1);
  assert.equal(Object.keys(result.session.board).length,3);
});

test('exchange returns replacements and advances the turn',()=>{
  const session=sampleSession();
  const result=exchangeFromRack(session,['c','a'],()=>0.5);
  assert.equal(result.ok,true);
  assert.equal(result.session.players[0].rack.length,7);
  assert.equal(result.session.bag.length,18);
  assert.equal(result.session.currentPlayer,1);
});

test('pass advances the turn and finishes after two complete cycles',()=>{
  let session=sampleSession();
  for(let i=0;i<3;i++)session=passTurn(session).session;
  assert.equal(session.currentPlayer,1);
  const final=passTurn(session);
  assert.equal(final.session.status,'finished');
  assert.ok(final.session.winner);
});
