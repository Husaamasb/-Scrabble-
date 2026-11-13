import React, { useEffect, useMemo, useState } from 'react';
import { PREMIUM, evaluateMove } from './game/engine.js';
import { createGameSession, commitTurn, exchangeFromRack, passTurn } from './game/session.js';
import { createWiktionaryValidator } from './game/wordValidator.js';
import { findBotMoves, orderBotMoves } from './game/bot.js';

const names = ['اللاعب الأول','اللاعب الثاني','اللاعب الثالث','اللاعب الرابع'];
function localSessionKey(language,botMode){return 'scrabble:local-session:'+language+':'+(botMode?'bot':'local');}
function loadLocalSession(language,botMode){try{const key=localSessionKey(language,botMode);const saved=JSON.parse(globalThis.localStorage?.getItem(key)||'null');if(saved?.version===1&&saved.session?.players?.length>=2)return saved.session;if(!botMode){const legacy=JSON.parse(globalThis.localStorage?.getItem('scrabble:local-session:'+language)||'null');if(legacy?.version===1&&legacy.session?.players?.length>=2)return legacy.session;}return null;}catch{return null;}}
export default function LocalTable({ language, onExit, botMode=false }) {
  const [count,setCount]=useState(2);
  const [difficulty,setDifficulty]=useState(3);
  const [chestOpen,setChestOpen]=useState(true);
  const [session,setSession]=useState(()=>loadLocalSession(language,botMode));
  const [pending,setPending]=useState([]);
  const [selected,setSelected]=useState(null);
  const [blankChoice,setBlankChoice]=useState('');
  const [exchange,setExchange]=useState([]);
  const [busy,setBusy]=useState(false);
  const [message,setMessage]=useState('');
  const [mode,setMode]=useState('local');
  const cells=useMemo(()=>Array.from({length:225},(_,i)=>i),[]);
  useEffect(()=>{try{const key=localSessionKey(language,botMode);if(session)globalThis.localStorage?.setItem(key,JSON.stringify({version:1,session}));else globalThis.localStorage?.removeItem(key);}catch{}},[session,language,botMode]);
  const ar=language==='ar';
  const start=()=>{const game=createGameSession(language,botMode?['أنت','البوت']:names.slice(0,count));game.matchId=globalThis.crypto?.randomUUID?.()||String(Date.now())+'-'+Math.random().toString(36).slice(2);setSession(game);setPending([]);setSelected(null);setExchange([]);setMessage('');};
  useEffect(()=>{
    if(!botMode||!session||session.status!=='playing'||session.currentPlayer!==1||busy)return;
    let cancelled=false;
    const runBot=async()=>{
      setBusy(true);setMessage(ar?'الكمبيوتر يفكر بحركته…':'The bot is thinking…');
      try{
        const moves=orderBotMoves(findBotMoves(session),difficulty);
        for(const move of moves){
          if(cancelled)return;
          const result=await commitTurn(session,move.placements,createWiktionaryValidator());
          if(result.ok){if(!cancelled){setSession(result.session);setMessage(ar?'لعب الكمبيوتر '+move.word+'  وجاب '+result.move.total+' نقطة.':'Bot played '+move.word+' for '+result.move.total+' points.');}return;}
        }
        if(!cancelled){setSession(passTurn(session).session);setMessage(ar?'الكمبيوتر ما لقى حركة مقبولة، فعدّى دوره.':'The bot found no accepted move and passed.');}
      }catch{if(!cancelled){setSession(passTurn(session).session);setMessage(ar?'ما قدر الكمبيوتر يكمل حركته.':'The bot could not complete its move.');}}
      finally{if(!cancelled)setBusy(false);}
    };
    runBot();return ()=>{cancelled=true;};
  },[botMode,session?.currentPlayer,session?.history?.length,session?.status,difficulty]);
  useEffect(()=>{
    if(!botMode||!session||session.status!=='finished'||!session.matchId)return;
    const awardKey='scrabble:xp-awarded:'+session.matchId;
    try{
      if(globalThis.localStorage?.getItem(awardKey))return;
      const data=JSON.parse(globalThis.localStorage?.getItem('scrabble:dashboard:v1')||'{}');
      const human=session.players[0],bot=session.players[1];
      const delta=human.score>bot.score?20:human.score===bot.score?15:-5;
      data.xp=(Number(data.xp)||0)+delta;
      globalThis.localStorage?.setItem('scrabble:dashboard:v1',JSON.stringify(data));
      globalThis.localStorage?.setItem(awardKey,'1');
      setMessage(ar?(delta===20?'فزت بالمباراة! كسبت 20 XP.':delta===15?'تعادل! كسبت 15 XP.':'خلصت المباراة. انخصم منك 5 XP.'):(delta===20?'You won! +20 XP.':delta===15?'Draw! +15 XP.':'Match lost. -5 XP.'));
    }catch{}
  },[botMode,session?.status,session?.matchId]);
  if(!session)return <section className="local-setup" dir={ar?'rtl':'ltr'}>
    <h2>{ar?'العبوا على نفس الجهاز':'Same-device multiplayer'}</h2>
    <p>{ar?'اختاروا عدد اللاعبين قبل تبدأ المباراة.':'Choose the player count before starting.'}</p>
    <label>{botMode?(ar?'مستوى الكمبيوتر':'Bot level'):(ar?'عدد اللاعبين':'Players')} <select value={botMode?difficulty:count} onChange={e=>botMode?setDifficulty(Number(e.target.value)):setCount(Number(e.target.value))}>{(botMode?[{value:1,ar:'سهل مرة',en:'Very easy'},{value:2,ar:'سهل',en:'Easy'},{value:3,ar:'متوسط',en:'Medium'},{value:4,ar:'صعب',en:'Hard'},{value:5,ar:'صعب مرة',en:'Very hard'}]:[2,3,4].map(n=>({value:n,ar:String(n),en:String(n)}))).map(option=><option key={option.value} value={option.value}>{ar?option.ar:option.en}</option>)}</select></label>
    {!botMode&&<div className="premium-editor">
    </div>}

    <button className="primary" onClick={start}>{ar?'ابدأ المباراة':'Start match'}</button>
    <button onClick={onExit}>{ar?'رجوع':'Back'}</button>
  </section>;
  const player=session.players[session.currentPlayer];
  const placedIds=new Set(pending.map(p=>p.tile.id));
  const visibleBoard={...session.board,...Object.fromEntries(pending.map(p=>[p.row*15+p.col,p.tile]))};
  const place=(index)=>{
    if(selected===null||visibleBoard[index]||busy)return;
    const tile=player.rack.find(t=>t.id===selected);if(!tile)return;
    if(tile.isBlank&&!blankChoice.trim()){setMessage(ar?'اكتب الحرف اللي بيمثله الجوكر أول.':'Enter the letter represented by the blank tile first.');return;}
    const placedTile=tile.isBlank?{...tile,blankAs:blankChoice.trim()}:tile;
    const next=[...pending,{row:Math.floor(index/15),col:index%15,tile:placedTile}];
    const check=evaluateMove(session.board,next,PREMIUM);
    if(check.reason==='occupied-square'||check.reason==='invalid-placement')return;
    setPending(next);setSelected(null);setBlankChoice('');setMessage('');
  };
  const undo=()=>{setPending(p=>p.slice(0,-1));setMessage('');};
  const confirm=async()=>{
    if(!pending.length||busy)return;
    setBusy(true);setMessage(ar?'نتحقق من الكلمات…':'Checking dictionary…');
    try{
      const result=await commitTurn(session,pending,createWiktionaryValidator());
      if(!result.ok){setMessage(ar?'ما قبلنا الحركة: '+result.reason:'Move rejected: '+result.reason);return;}
      setSession(result.session);setPending([]);setSelected(null);setExchange([]);
      setMessage(ar?'تم قبول الحركة وإضافة '+result.move.total+' نقطة.':'Move accepted: '+result.move.total+' points.');
    }catch{setMessage(ar?'ما قدرنا نتصل بالقاموس.':'Dictionary connection failed.');}
    finally{setBusy(false);}
  };
  const doPass=()=>{if(pending.length){setMessage(ar?'رجّع القطع اللي حطيتها أول.':'Undo placed tiles first.');return;}const result=passTurn(session);setSession(result.session);setMessage(result.session.status==='finished'?(ar?'خلصت المباراة.':'Match finished.'):(ar?'عدّيت دورك.':'Turn passed.'));};
  const doExchange=()=>{if(pending.length||!exchange.length){setMessage(ar?'حدد القطع اللي تبي تبدّلها بعد ما تلغي الحركة الحالية.':'Select tiles to exchange after clearing the current move.');return;}const result=exchangeFromRack(session,exchange);if(!result.ok){setMessage(ar?'ما قدرنا نبدّل القطع: '+result.reason:'Exchange failed: '+result.reason);return;}setSession(result.session);setExchange([]);setMessage(ar?'بدّلت القطع وخلص دورك.':'Tiles exchanged; your turn is over.');};
  return <main className="local-table" dir={ar?'rtl':'ltr'}>
    <header className="local-header"><div><small>{botMode?(ar?'مباراة ضد الكمبيوتر':'VS BOT'):(ar?'مباراة على نفس الجهاز':'LOCAL MATCH')}</small><h2>{session.status==='finished'?(ar?'خلصت المباراة':'Match finished'):(ar?'دور':'Turn')+' — '+player.name}</h2></div><button onClick={onExit}>{ar?'اطلع':'Exit'}</button></header>
    <div className="local-scores">{session.players.map((p,i)=><div className={i===session.currentPlayer?'current':''} key={p.id}><span>{p.name}</span><b>{p.score}</b><small>{ar?'قطع':'Tiles'}: {p.rack.length}</small></div>)}</div>
    <section className="chest-panel"><div className="chest-heading"><h3>{ar?'صندوق الحروف الخشبي':'Wooden letter chest'}</h3><strong>{session.bag.length} {ar?'قطعة باقية':'tiles left'}</strong></div><button type="button" className={'chest-lid '+(chestOpen?'open':'closed')} aria-expanded={chestOpen} onClick={()=>setChestOpen(value=>!value)}>{chestOpen?(ar?'✦ الصندوق مفتوح · اضغط عشان تقفل الغطاء':'✦ Chest open · tap to close lid'):(ar?'✦ اضغط عشان تفتح صندوق الحروف':'✦ Tap to open the letter chest')}</button>{chestOpen&&<div className="chest-row">{session.bag.map((_,i)=><span key={i} className="chest-tile face-down" aria-hidden="true"><b>✦</b><small>SCRABBLE</small></span>)}</div>}<p>{ar?'القطع مقلوبة، وتتعبّى تلقائي بعد ما تعتمد حركتك.':'Tiles stay face down and refill automatically after a move is accepted.'}</p></section>
    {session.status==='finished'&&<><h2 className="winner">{ar?'الفايز: ':'Winner: '}{session.players.find(p=>p.id===session.winner)?.name}</h2><button className="primary" onClick={()=>setSession(null)}>{ar?'ابدأ مباراة جديدة':'Start a new match'}</button></>}
    <div className="local-board-area"><div className="board">{cells.map(i=>{const tile=visibleBoard[i];const p=PREMIUM[i]||'';return <button key={i} className={'cell '+(tile?'filled':p.toLowerCase())} disabled={busy||session.status==='finished'} onClick={()=>place(i)}>{tile?<><b>{tile.blankAs||tile.letter}</b><small>{tile.points}</small></>:p==='TW'?(ar?'ك×3':'3W'):p==='DW'?(ar?'ك×2':'2W'):p==='TL'?(ar?'ح×3':'3L'):p==='DL'?(ar?'ح×2':'2L'):i===112?'★':''}</button>;})}</div></div>
    {session.status==='playing'&&<section className="local-controls">
      <h3>{ar?'قطع ':'Rack — '}{player.name}</h3>
      <div className="rack">{player.rack.map(tile=><button key={tile.id} className={'tile '+(selected===tile.id?'chosen':'')+(selected===tile.id||exchange.includes(tile.id)?' chosen':'')} disabled={busy||placedIds.has(tile.id)} onClick={()=>{if(pending.length===0&&exchange.length>0){setExchange(v=>v.includes(tile.id)?v.filter(x=>x!==tile.id):[...v,tile.id]);}else setSelected(tile.id);}}><b>{tile.letter}</b><small>{tile.points}</small></button>)}</div>
      {selected&&player.rack.find(t=>t.id===selected)?.isBlank&&<label className="blank-choice">{ar?'الحرف الذي يمثله الجوكر':'Letter for blank tile'}<input value={blankChoice} onChange={e=>setBlankChoice(ar?e.target.value:e.target.value.toUpperCase())} maxLength={ar?3:1}/></label>}
      <div className="local-actions"><button className="primary" onClick={confirm} disabled={busy||!pending.length}>{ar?'اعتماد الكلمة':'Confirm move'}</button><button onClick={undo} disabled={busy||!pending.length}>{ar?'تراجع عن قطعة':'Undo tile'}</button><button onClick={()=>{setPending([]);setSelected(null);}} disabled={busy||!pending.length}>{ar?'إلغاء الحركة':'Cancel move'}</button><button onClick={()=>setExchange(v=>v.length?[]:player.rack.map(t=>t.id))} disabled={busy||pending.length>0||session.bag.length<player.rack.length}>{ar?'حدد قطع للتبديل':'Select exchange tiles'}</button><button onClick={doExchange} disabled={busy||!exchange.length}>{ar?'بدّل المحدد':'Exchange selected'}</button><button onClick={doPass} disabled={busy}>{ar?'عدّي الدور':'Pass turn'}</button></div>
      <p className="local-bag">{ar?'القطع الباقية بالصندوق: ':'Tiles left in bag: '}{session.bag.length}</p>
    </section>}
    {message&&<p className="message">{message}</p>}
    <section className="local-history"><h3>{ar?'سجل المباراة':'Match history'}</h3>{session.history.slice().reverse().map((entry,i)=><p key={i}>{session.players.find(p=>p.id===entry.playerId)?.name}: {entry.words.map(w=>w.letters).join('، ')} (+{entry.points})</p>)}</section>
  </main>;
}
