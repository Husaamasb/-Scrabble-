import { applyMove, evaluateMove } from './engine.js';
import { createTileBag, drawTiles, exchangeTiles, settleEndgame } from './tiles.js';
import { validateWords } from './wordValidator.js';

const makeId=(random)=>`tile-${Math.floor(random()*1e12).toString(36)}-${Math.random().toString(36).slice(2,7)}`;
const addIds=(tiles,random)=>tiles.map(tile=>({...tile,id:makeId(random)}));

export function createGameSession(language, playerNames, random=Math.random) {
  if (!Array.isArray(playerNames)||playerNames.length<2||playerNames.length>4) {
    throw new Error('A Scrabble session needs 2 to 4 players');
  }
  const bag=createTileBag(language,random);
  const players=playerNames.map((name,index)=>{
    const draw=drawTiles(bag,7);
    bag.splice(0,draw.drawn.length);
    return {id:`player-${index+1}`,name,score:0,rack:addIds(draw.drawn,random)};
  });
  return {language,players,board:{},bag,currentPlayer:0,consecutivePasses:0,status:'playing',winner:null,history:[]};
}

export async function commitTurn(session, placements, dictionaryValidator) {
  if(session.status!=='playing') return {ok:false,reason:'game-finished'};
  const player=session.players[session.currentPlayer];
  const rackIds=new Set(player.rack.map(tile=>tile.id));
  if(placements.some(p=>!rackIds.has(p.tile?.id))) return {ok:false,reason:'tile-not-in-current-rack'};
  const evaluation=evaluateMove(session.board,placements);
  if(!evaluation.valid) return {ok:false,reason:evaluation.reason};
  const dictionary=await validateWords(evaluation.words,session.language,dictionaryValidator);
  if(!dictionary.valid) return {ok:false,reason:dictionary.reason||'word-not-accepted',dictionary};

  const applied=applyMove(session.board,placements);
  const used=new Set(placements.map(p=>p.tile.id));
  const remainingRack=player.rack.filter(tile=>!used.has(tile.id));
  const draw=drawTiles(session.bag,7-remainingRack.length);
  const nextRack=[...remainingRack,...addIds(draw.drawn,Math.random)];
  const nextPlayers=session.players.map((p,index)=>index===session.currentPlayer
    ? {...p,score:p.score+applied.total,rack:nextRack} : p);
  const next={...session,players:nextPlayers,board:applied.board,bag:draw.remaining,consecutivePasses:0,
    history:[...session.history,{playerId:player.id,words:applied.words,points:applied.total}]};
  if(nextRack.length===0&&next.bag.length===0){
    const finalScores=settleEndgame(next.players.map(p=>p.score),next.players.map(p=>p.rack),session.currentPlayer);
    next.players=next.players.map((p,index)=>({...p,score:finalScores[index]}));
    next.status='finished';
    next.winner=[...next.players].sort((a,b)=>b.score-a.score)[0].id;
    return {ok:true,session:next,move:applied,finished:true};
  }
  next.currentPlayer=(session.currentPlayer+1)%session.players.length;
  return {ok:true,session:next,move:applied,finished:false};
}

export function exchangeFromRack(session, tileIds, random=Math.random) {
  if(session.status!=='playing') return {ok:false,reason:'game-finished'};
  if(!Array.isArray(tileIds)||tileIds.length===0) return {ok:false,reason:'no-tiles-selected'};
  const player=session.players[session.currentPlayer];
  const selected=player.rack.filter(tile=>tileIds.includes(tile.id));
  if(selected.length!==tileIds.length) return {ok:false,reason:'tile-not-in-current-rack'};
  const exchange=exchangeTiles(session.bag,selected,random);
  if(!exchange.valid) return {ok:false,reason:exchange.reason};
  const selectedIds=new Set(tileIds);
  const replacement=addIds(exchange.replacements,random);
  const nextPlayers=session.players.map((p,index)=>index===session.currentPlayer
    ? {...p,rack:[...p.rack.filter(tile=>!selectedIds.has(tile.id)),...replacement]} : p);
  return {ok:true,session:{...session,players:nextPlayers,bag:exchange.remaining,
    currentPlayer:(session.currentPlayer+1)%session.players.length,consecutivePasses:0}};
}

export function passTurn(session) {
  if(session.status!=='playing') return {ok:false,reason:'game-finished'};
  const passes=session.consecutivePasses+1;
  if(passes>=session.players.length*2){
    const finalScores=settleEndgame(session.players.map(p=>p.score),session.players.map(p=>p.rack),-1);
    // Passing ends a practice session without a finisher bonus: subtract each rack from its owner.
    const players=session.players.map((p,index)=>({...p,score:p.score-p.rack.reduce((sum,t)=>sum+t.points,0)}));
    const winner=[...players].sort((a,b)=>b.score-a.score)[0].id;
    return {ok:true,session:{...session,players,status:'finished',winner,consecutivePasses:passes}};
  }
  return {ok:true,session:{...session,currentPlayer:(session.currentPlayer+1)%session.players.length,consecutivePasses:passes}};
}
