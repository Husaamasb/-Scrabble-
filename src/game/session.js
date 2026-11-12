import { applyMove, evaluateMove } from './engine.js';
import { createTileBag, drawTiles, exchangeTiles, settleEndgame } from './tiles.js';
import { validateWords } from './wordValidator.js';


const EN_ORDER='ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const AR_ORDER='ابتثجحخدذرزسشصضطظعغفقكلمنهوي';
const AR_ALIASES={ا:0,أ:0,إ:0,آ:0,ء:0,ؤ:0,ئ:0,'ئ أول الكلمة':0,'ئ شكل آخر':0,ة:25,ى:27,يء:27,لا:22,لأ:22,لإ:22,لآ:22};
function letterRank(letter,language){
  if(letter==='★')return Number.POSITIVE_INFINITY;
  if(language==='en'){const rank=EN_ORDER.indexOf(String(letter).toUpperCase());return rank<0?Number.POSITIVE_INFINITY:rank;}
  if(Object.hasOwn(AR_ALIASES,letter))return AR_ALIASES[letter];
  const rank=AR_ORDER.indexOf(letter);return rank<0?Number.POSITIVE_INFINITY:rank;
}

export function chooseStartingPlayer(drawnLetters,language){
  if(!Array.isArray(drawnLetters)||drawnLetters.length<2||drawnLetters.length>4)throw new Error('Draw two to four starting tiles');
  const ranks=drawnLetters.map(letter=>letterRank(letter,language));
  const best=Math.min(...ranks);
  const winners=ranks.map((rank,index)=>rank===best?index:-1).filter(index=>index>=0);
  return winners.length===1?{tie:false,playerIndex:winners[0]}:{tie:true,playerIndices:winners};
}

const makeId=(random,serial)=>`tile-${Math.floor(random()*1e12).toString(36)}-${serial.toString(36)}`;
const addIds=(tiles,random,startSerial=0)=>tiles.map((tile,index)=>({...tile,id:makeId(random,startSerial+index)}));

function shuffleInPlace(items,random){
  for(let i=items.length-1;i>0;i--){const j=Math.floor(random()*(i+1));[items[i],items[j]]=[items[j],items[i]];}
}
function drawStartingOrder(bag,playerCount,language,random){
  let eligible=Array.from({length:playerCount},(_,i)=>i);
  const history=[];
  for(let round=0;round<100;round++){
    if(bag.length<eligible.length)throw new Error('Not enough tiles for starting draw');
    const drawn=eligible.map(()=>bag.shift());
    const decision=chooseStartingPlayer(drawn.map(tile=>tile.letter),language);
    history.push({players:[...eligible],letters:drawn.map(tile=>tile.letter)});
    bag.push(...drawn);
    shuffleInPlace(bag,random);
    if(!decision.tie)return {playerIndex:eligible[decision.playerIndex],history};
    eligible=decision.playerIndices.map(index=>eligible[index]);
  }
  return {playerIndex:eligible[0],history,tieBreakLimitReached:true};
}

export function createGameSession(language, playerNames, random=Math.random) {
  if (!Array.isArray(playerNames)||playerNames.length<2||playerNames.length>4) {
    throw new Error('A Scrabble session needs 2 to 4 players');
  }
  const bag=createTileBag(language,random);
  const starter=drawStartingOrder(bag,playerNames.length,language,random);
  let tileSerial=0;
  const players=playerNames.map((name,index)=>{
    const draw=drawTiles(bag,7);
    bag.splice(0,draw.drawn.length);
    const rack=addIds(draw.drawn,random,tileSerial);
    tileSerial+=draw.drawn.length;
    return {id:`player-${index+1}`,name,score:0,rack};
  });
  return {language,players,board:{},bag,currentPlayer:starter.playerIndex,tileSerial,startingDraws:starter.history,
    consecutivePasses:0,status:'playing',winner:null,history:[]};
}

export async function commitTurn(session, placements, dictionaryValidator, random=Math.random) {
  if(session.status!=='playing') return {ok:false,reason:'game-finished'};
  if(!Array.isArray(placements)||placements.length===0) return {ok:false,reason:'empty-move'};
  const player=session.players[session.currentPlayer];
  const rackIds=new Set(player.rack.map(tile=>tile.id));
  const placedIds=placements.map(p=>p.tile?.id);
  if(placedIds.some(id=>!rackIds.has(id))) return {ok:false,reason:'tile-not-in-current-rack'};
  if(new Set(placedIds).size!==placedIds.length) return {ok:false,reason:'duplicate-tile'};
  const evaluation=evaluateMove(session.board,placements);
  if(!evaluation.valid) return {ok:false,reason:evaluation.reason};
  const dictionary=await validateWords(evaluation.words,session.language,dictionaryValidator);
  if(!dictionary.valid) return {ok:false,reason:dictionary.reason||'word-not-accepted',dictionary};

  const applied=applyMove(session.board,placements);
  const used=new Set(placements.map(p=>p.tile.id));
  const remainingRack=player.rack.filter(tile=>!used.has(tile.id));
  const draw=drawTiles(session.bag,7-remainingRack.length);
  const nextRack=[...remainingRack,...addIds(draw.drawn,random,session.tileSerial||0)];
  const nextPlayers=session.players.map((p,index)=>index===session.currentPlayer
    ? {...p,score:p.score+applied.total,rack:nextRack} : p);
  const next={...session,tileSerial:(session.tileSerial||0)+draw.drawn.length,players:nextPlayers,board:applied.board,bag:draw.remaining,consecutivePasses:0,
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
  const replacement=addIds(exchange.replacements,random,session.tileSerial||0);
  const nextPlayers=session.players.map((p,index)=>index===session.currentPlayer
    ? {...p,rack:[...p.rack.filter(tile=>!selectedIds.has(tile.id)),...replacement]} : p);
  return {ok:true,session:{...session,tileSerial:(session.tileSerial||0)+replacement.length,players:nextPlayers,bag:exchange.remaining,
    currentPlayer:(session.currentPlayer+1)%session.players.length,consecutivePasses:0}};
}

export function passTurn(session) {
  if(session.status!=='playing') return {ok:false,reason:'game-finished'};
  const passes=session.consecutivePasses+1;
  if(passes>=session.players.length*2){
    // If everyone passes twice in succession, subtract each player's remaining rack.
    const players=session.players.map((p,index)=>({...p,score:p.score-p.rack.reduce((sum,t)=>sum+t.points,0)}));
    const winner=[...players].sort((a,b)=>b.score-a.score)[0].id;
    return {ok:true,session:{...session,players,status:'finished',winner,consecutivePasses:passes}};
  }
  return {ok:true,session:{...session,currentPlayer:(session.currentPlayer+1)%session.players.length,consecutivePasses:passes}};
}
