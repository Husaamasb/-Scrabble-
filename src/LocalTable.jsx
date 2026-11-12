import React, { useEffect, useMemo, useState } from 'react';
import { PREMIUM, evaluateMove } from './game/engine.js';
import { createGameSession, commitTurn, exchangeFromRack, passTurn } from './game/session.js';
import { createWiktionaryValidator } from './game/wordValidator.js';

const names = ['اللاعب الأول','اللاعب الثاني','اللاعب الثالث','اللاعب الرابع'];
function loadLocalSession(language){try{const saved=JSON.parse(globalThis.localStorage?.getItem('scrabble:local-session:'+language)||'null');return saved?.version===1&&saved.session?.players?.length>=2?saved.session:null;}catch{return null;}}
const BOT_WORDS={
  en:'act age air all and ant any ape arm art ask bad bag bar bat bed bee beg bet big bit box boy bus buy cab can cap car cat cow cup cut day den did dog dry ear eat egg end eye fan far fat few fit fly fog fox fun gas get god got gun hat her hit hot ice ink jam jar jet job joy key kid kit lab law lay leg let lip log lot low man map mat may men mix mom mud mug net new nod not now nut oil old one out owl own pan pat pay pen pet pie pig pin pit pot put rag ran rat raw red rid rig rip rob rod row rub run sad sat saw say sea see set she shy sin sit six sky son sun tag tan tap tar tea ten the tie tin tip toe top toy try two use van war was way web wet who why win yes zoo'.split(' '),
  ar:'اب اخذ اذا ازر اسد اسم اكل ام امر امن انا انت اهل باب بحر بئر بيت تاج تام تين جمل جبل جيد حبر حجر حبل حرب حسن حصن حقل حلم حمد حوت خبر خبز خرج دخل درس درب درع ذهب ذيل ربح رعد رمل روح زاد زار زهر زيت سار سبب سحر سحب سرق سطر سفر سهل سمع شجر شمس صبر صخر صبح صدر صيد ضرب طبع طير ظهر عجب عسل عمل عمر عين غاب غرف غرس غزل فاز فتح فجر فكر فلك فهم فوز قلب قلم قمر كاس كتب كلب كلم كمل كنز لعب لحم ليل لون مال مات ملك ملح منع موت نار نجم نهر نور نوم هرب هدى هزم ورد وعد وقت ولد يوم'.split(' ')
};
function findBotMoves(session){
 const words=BOT_WORDS[session.language]||[], rack=session.players[session.currentPlayer].rack, moves=[];
 for(const word of words){if(word.length<2||word.length>7)continue;
  for(let vertical=0;vertical<2;vertical++)for(let row=0;row<15;row++)for(let col=0;col<15;col++){
   if(row+(vertical?word.length-1:0)>14||col+(vertical?0:word.length-1)>14)continue;
   let valid=true,remaining=[...rack],placements=[];
   for(let i=0;i<word.length;i++){const rr=row+(vertical?i:0),cc=col+(vertical?0:i),existing=session.board[rr*15+cc];
    if(existing){if((existing.blankAs||existing.letter)!==word[i]){valid=false;break;}continue;}
    let ti=remaining.findIndex(t=>t.letter===word[i]);if(ti<0)ti=remaining.findIndex(t=>t.isBlank);if(ti<0){valid=false;break;}
    const tile=remaining.splice(ti,1)[0];placements.push({row:rr,col:cc,tile:tile.isBlank?{...tile,blankAs:word[i]}:tile});
   }
   if(!valid||!placements.length)continue;const result=evaluateMove(session.board,placements);if(result.valid)moves.push({placements,points:result.total,word});
  }
 }
 const unique=new Map();for(const move of moves){const key=move.placements.map(p=>p.row*15+p.col).sort((a,b)=>a-b).join(',');if(!unique.has(key))unique.set(key,move);}
 return [...unique.values()].sort((a,b)=>b.points-a.points);
}
export default function LocalTable({ language, onExit, botMode=false }) {
  const [count,setCount]=useState(2);
  const [difficulty,setDifficulty]=useState(3);
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
  const start=()=>{setSession(createGameSession(language,botMode?['أنت','البوت']:names.slice(0,count)));setPending([]);setSelected(null);setExchange([]);setMessage('');};
  useEffect(()=>{
    if(!botMode||!session||session.status!=='playing'||session.currentPlayer!==1||busy)return;
    let cancelled=false;
    const runBot=async()=>{
      setBusy(true);setMessage(ar?'البوت يفكر في حركته…':'The bot is thinking…');
      try{
        const moves=findBotMoves(session);
        const count=Math.min(moves.length,Math.max(1,difficulty*3));
        for(const move of moves.slice(0,count)){
          if(cancelled)return;
          const result=await commitTurn(session,move.placements,createWiktionaryValidator());
          if(result.ok){if(!cancelled){setSession(result.session);setMessage(ar?'لعب البوت '+move.word+' وحصل على '+result.move.total+' نقطة.':'Bot played '+move.word+' for '+result.move.total+' points.');}return;}
        }
        if(!cancelled){setSession(passTurn(session).session);setMessage(ar?'لم يجد البوت حركة مقبولة فتجاوز دوره.':'The bot found no accepted move and passed.');}
      }catch{if(!cancelled){setSession(passTurn(session).session);setMessage(ar?'تعذر إكمال حركة البوت.':'The bot could not complete its move.');}}
      finally{if(!cancelled)setBusy(false);}
    };
    runBot();return ()=>{cancelled=true;};
  },[botMode,session?.currentPlayer,session?.history?.length,session?.status,difficulty]);
  if(!session)return <section className="local-setup" dir={ar?'rtl':'ltr'}>
    <h2>{ar?'لعب جماعي على نفس الجهاز':'Same-device multiplayer'}</h2>
    <p>{ar?'اختاروا عدد اللاعبين، ومرروا الجهاز بعد نهاية كل دور.':'Choose the player count and pass the device after each turn.'}</p>
    <label>{botMode?(ar?'مستوى البوت':'Bot level'):(ar?'عدد اللاعبين':'Players')} <select value={botMode?difficulty:count} onChange={e=>botMode?setDifficulty(Number(e.target.value)):setCount(Number(e.target.value))}>{(botMode?[1,2,3,4,5]:[2,3,4]).map(n=><option key={n} value={n}>{n}</option>)}</select></label>
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
    <header className="local-header"><div><small>{botMode?(ar?'مباراة ضد البوت':'VS BOT'):(ar?'مباراة محلية':'LOCAL MATCH')}</small><h2>{session.status==='finished'?(ar?'انتهت المباراة':'Match finished'):(ar?'دور':'Turn')+' — '+player.name}</h2></div><button onClick={onExit}>{ar?'خروج':'Exit'}</button></header>
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
