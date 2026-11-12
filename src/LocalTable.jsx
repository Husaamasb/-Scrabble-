import React, { useEffect, useMemo, useState } from 'react';
import { PREMIUM, evaluateMove } from './game/engine.js';
import { createGameSession, commitTurn, exchangeFromRack, passTurn } from './game/session.js';
import { createWiktionaryValidator } from './game/wordValidator.js';

const names = ['اللاعب الأول','اللاعب الثاني','اللاعب الثالث','اللاعب الرابع'];
function loadLocalSession(language){try{const saved=JSON.parse(globalThis.localStorage?.getItem('scrabble:local-session:'+language)||'null');return saved?.version===1&&saved.session?.players?.length>=2?saved.session:null;}catch{return null;}}
export default function LocalTable({ language, onExit }) {
  const [count,setCount]=useState(2);
  const [session,setSession]=useState(()=>loadLocalSession(language));
  const [pending,setPending]=useState([]);
  const [selected,setSelected]=useState(null);
  const [blankChoice,setBlankChoice]=useState('');
  const [exchange,setExchange]=useState([]);
  const [busy,setBusy]=useState(false);
  const [message,setMessage]=useState('');
  const [mode,setMode]=useState('local');
  const cells=useMemo(()=>Array.from({length:225},(_,i)=>i),[]);
  useEffect(()=>{try{if(session)globalThis.localStorage?.setItem('scrabble:local-session:'+language,JSON.stringify({version:1,session}));else globalThis.localStorage?.removeItem('scrabble:local-session:'+language);}catch{}},[session,language]);
  const ar=language==='ar';
  const start=()=>{setSession(createGameSession(language,names.slice(0,count)));setPending([]);setSelected(null);setExchange([]);setMessage('');};
  if(!session)return <section className="local-setup" dir={ar?'rtl':'ltr'}>
    <h2>{ar?'لعب جماعي على نفس الجهاز':'Same-device multiplayer'}</h2>
    <p>{ar?'اختاروا عدد اللاعبين، ومرروا الجهاز بعد نهاية كل دور.':'Choose the player count and pass the device after each turn.'}</p>
    <label>{ar?'عدد اللاعبين':'Players'} <select value={count} onChange={e=>setCount(Number(e.target.value))}>{[2,3,4].map(n=><option key={n} value={n}>{n}</option>)}</select></label>
    <button className="primary" onClick={start}>{ar?'ابدأ المباراة':'Start match'}</button>
    <button onClick={onExit}>{ar?'رجوع':'Back'}</button>
  </section>;
  const player=session.players[session.currentPlayer];
  const placedIds=new Set(pending.map(p=>p.tile.id));
  const visibleBoard={...session.board,...Object.fromEntries(pending.map(p=>[p.row*15+p.col,p.tile]))};
  const place=(index)=>{
    if(selected===null||visibleBoard[index]||busy)return;
    const tile=player.rack.find(t=>t.id===selected);if(!tile)return;
    if(tile.isBlank&&!blankChoice.trim()){setMessage(ar?'اكتب الحرف الذي يمثله الجوكر أولاً.':'Enter the letter represented by the blank tile first.');return;}
    const placedTile=tile.isBlank?{...tile,blankAs:blankChoice.trim()}:tile;
    const next=[...pending,{row:Math.floor(index/15),col:index%15,tile:placedTile}];
    const check=evaluateMove(session.board,next);
    if(check.reason==='occupied-square'||check.reason==='invalid-placement')return;
    setPending(next);setSelected(null);setBlankChoice('');setMessage('');
  };
  const undo=()=>{setPending(p=>p.slice(0,-1));setMessage('');};
  const confirm=async()=>{
    if(!pending.length||busy)return;
    setBusy(true);setMessage(ar?'جارٍ التحقق من الكلمات…':'Checking dictionary…');
    try{
      const result=await commitTurn(session,pending,createWiktionaryValidator());
      if(!result.ok){setMessage(ar?'لم تُقبل الحركة: '+result.reason:'Move rejected: '+result.reason);return;}
      setSession(result.session);setPending([]);setSelected(null);setExchange([]);
      setMessage(ar?'تم قبول الحركة وإضافة '+result.move.total+' نقطة.':'Move accepted: '+result.move.total+' points.');
    }catch{setMessage(ar?'تعذر الاتصال بالقاموس.':'Dictionary connection failed.');}
    finally{setBusy(false);}
  };
  const doPass=()=>{if(pending.length){setMessage(ar?'أزل القطع الموضوعة أولاً.':'Undo placed tiles first.');return;}const result=passTurn(session);setSession(result.session);setMessage(result.session.status==='finished'?(ar?'انتهت المباراة.':'Match finished.'):(ar?'تم تجاوز الدور.':'Turn passed.'));};
  const doExchange=()=>{if(pending.length||!exchange.length){setMessage(ar?'حدد قطعاً للتبديل بعد إزالة الحركة الحالية.':'Select tiles to exchange after clearing the current move.');return;}const result=exchangeFromRack(session,exchange);if(!result.ok){setMessage(ar?'تعذر تبديل القطع: '+result.reason:'Exchange failed: '+result.reason);return;}setSession(result.session);setExchange([]);setMessage(ar?'تم تبديل القطع وانتهى دورك.':'Tiles exchanged; your turn is over.');};
  return <main className="local-table" dir={ar?'rtl':'ltr'}>
    <header className="local-header"><div><small>{ar?'مباراة محلية':'LOCAL MATCH'}</small><h2>{session.status==='finished'?(ar?'انتهت المباراة':'Match finished'):(ar?'دور':'Turn')+' — '+player.name}</h2></div><button onClick={onExit}>{ar?'خروج':'Exit'}</button></header>
    <div className="local-scores">{session.players.map((p,i)=><div className={i===session.currentPlayer?'current':''} key={p.id}><span>{p.name}</span><b>{p.score}</b><small>{ar?'قطع':'Tiles'}: {p.rack.length}</small></div>)}</div>
    {session.status==='finished'&&<><h2 className="winner">{ar?'الفائز: ':'Winner: '}{session.players.find(p=>p.id===session.winner)?.name}</h2><button className="primary" onClick={()=>setSession(null)}>{ar?'ابدأ مباراة جديدة':'Start a new match'}</button></>}
    <div className="local-board-area"><div className="board">{cells.map(i=>{const tile=visibleBoard[i];const p=PREMIUM[i]||'';return <button key={i} className={'cell '+(tile?'filled':p.toLowerCase())} disabled={busy||session.status==='finished'} onClick={()=>place(i)}>{tile?<><b>{tile.blankAs||tile.letter}</b><small>{tile.points}</small></>:p==='TW'?'3W':p==='DW'?'2W':p==='TL'?'3L':p==='DL'?'2L':i===112?'★':''}</button>;})}</div></div>
    {session.status==='playing'&&<section className="local-controls">
      <h3>{ar?'قطع ':'Rack — '}{player.name}</h3>
      <div className="rack">{player.rack.map(tile=><button key={tile.id} className={'tile '+(selected===tile.id?'chosen':'')+(selected===tile.id||exchange.includes(tile.id)?' chosen':'')} disabled={busy||placedIds.has(tile.id)} onClick={()=>{if(pending.length===0&&exchange.length>0){setExchange(v=>v.includes(tile.id)?v.filter(x=>x!==tile.id):[...v,tile.id]);}else setSelected(tile.id);}}><b>{tile.letter}</b><small>{tile.points}</small></button>)}</div>
      {selected&&player.rack.find(t=>t.id===selected)?.isBlank&&<label className="blank-choice">{ar?'الحرف الذي يمثله الجوكر':'Letter for blank tile'}<input value={blankChoice} onChange={e=>setBlankChoice(ar?e.target.value:e.target.value.toUpperCase())} maxLength={ar?3:1}/></label>}
      <div className="local-actions"><button className="primary" onClick={confirm} disabled={busy||!pending.length}>{ar?'تأكيد الكلمة':'Confirm move'}</button><button onClick={undo} disabled={busy||!pending.length}>{ar?'تراجع عن قطعة':'Undo tile'}</button><button onClick={()=>{setPending([]);setSelected(null);}} disabled={busy||!pending.length}>{ar?'إلغاء الحركة':'Cancel move'}</button><button onClick={()=>setExchange(v=>v.length?[]:player.rack.map(t=>t.id))} disabled={busy||pending.length>0||session.bag.length<player.rack.length}>{ar?'تحديد قطع للتبديل':'Select exchange tiles'}</button><button onClick={doExchange} disabled={busy||!exchange.length}>{ar?'تبديل المحدد':'Exchange selected'}</button><button onClick={doPass} disabled={busy}>{ar?'تجاوز الدور':'Pass turn'}</button></div>
      <p className="local-bag">{ar?'القطع المتبقية في الصندوق: ':'Tiles left in bag: '}{session.bag.length}</p>
    </section>}
    {message&&<p className="message">{message}</p>}
    <section className="local-history"><h3>{ar?'سجل المباراة':'Match history'}</h3>{session.history.slice().reverse().map((entry,i)=><p key={i}>{session.players.find(p=>p.id===entry.playerId)?.name}: {entry.words.map(w=>w.letters).join('، ')} (+{entry.points})</p>)}</section>
  </main>;
}
