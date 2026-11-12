/** Order candidate moves according to the selected bot skill.
 * Moves are expected to be sorted from highest to lowest score.
 * Easier levels explore a wider range; harder levels focus on stronger moves.
 */

import { evaluateMove } from './engine.js';

const BOT_WORDS={
 en:'act age air all and ant any ape arm art ask bad bag bar bat bed bee beg bet big bit box boy bus buy cab can cap car cat cow cup cut day den did dog dry ear eat egg end eye fan far fat few fit fly fog fox fun gas get god got gun hat her hit hot ice ink jam jar jet job joy key kid kit lab law lay leg let lip log lot low man map mat may men mix mom mud mug net new nod not now nut oil old one out owl own pan pat pay pen pet pie pig pin pit pot put rag ran rat raw red rid rig rip rob rod row rub run sad sat saw say sea see set she shy sin sit six sky son sun tag tan tap tar tea ten the tie tin tip toe top toy try two use van war was way web wet who why win yes zoo scrabbles'.split(' '),
 ar:'اب اخذ اذا ازر اسد اسم اكل ام امر امن انا انت اهل باب بحر بئر بيت تاج تام تين جمل جبل جيد حبر حجر حبل حرب حسن حصن حقل حلم حمد حوت خبر خبز خرج دخل درس درب درع ذهب ذيل ربح رعد رمل روح زاد زار زهر زيت سار سبب سحر سحب سرق سطر سفر سهل سمع شجر شمس صبر صخر صبح صدر صيد ضرب طبع طير ظهر عجب عسل عمل عمر عين غاب غرف غرس غزل فاز فتح فجر فكر فلك فهم فوز قلب قلم قمر كاس كتب كلب كلم كمل كنز لعب لحم ليل لون مال مات ملك ملح منع موت نار نجم نهر نور نوم هرب هدى هزم ورد وعد وقت ولد يوم'.split(' ')
};

/** Find legal placements from the built-in candidate vocabulary. */
export function findBotMoves(session, vocabulary=BOT_WORDS[session.language]||[]) {
 const rack=session.players[session.currentPlayer].rack, moves=[];
 for(const word of vocabulary){if(word.length<2||word.length>15)continue;
  for(let vertical=0;vertical<2;vertical++)for(let row=0;row<15;row++)for(let col=0;col<15;col++){
   if(row+(vertical?word.length-1:0)>14||col+(vertical?0:word.length-1)>14)continue;
   let valid=true,remaining=[...rack],placements=[];
   for(let i=0;i<word.length;i++){const rr=row+(vertical?i:0),cc=col+(vertical?0:i),existing=session.board[rr*15+cc];
    if(existing){if((existing.blankAs||existing.letter)!==word[i]){valid=false;break;}continue;}
    let ti=remaining.findIndex(t=>t.letter===word[i]);if(ti<0)ti=remaining.findIndex(t=>t.isBlank);if(ti<0){valid=false;break;}
    const tile=remaining.splice(ti,1)[0];placements.push({row:rr,col:cc,tile:tile.isBlank?{...tile,blankAs:word[i]}:tile});
   }
   if(!valid||!placements.length)continue;const result=evaluateMove(session.board,placements,session.premiumLayout);if(result.valid)moves.push({placements,points:result.total,word});
  }
 }
 const unique=new Map();for(const move of moves){const key=move.placements.map(p=>p.row*15+p.col).sort((a,b)=>a-b).join(',');if(!unique.has(key))unique.set(key,move);}
 return [...unique.values()].sort((a,b)=>b.points-a.points);
}

export function orderBotMoves(moves, difficulty=3, random=Math.random) {
  if (!Array.isArray(moves) || moves.length < 2) return [...(moves||[])];
  const level=Math.max(1,Math.min(5,Math.floor(Number(difficulty)||3)));
  const ratios={1:1,2:0.75,3:0.5,4:0.25,5:0.1};
  const poolSize=Math.max(1,Math.ceil(moves.length*ratios[level]));
  const preferred=moves.slice(0,poolSize);
  const fallback=moves.slice(poolSize);
  const shuffle=items=>{
    const result=[...items];
    for(let i=result.length-1;i>0;i--){
      const j=Math.floor(Math.max(0,Math.min(0.999999999,random()))*(i+1));
      [result[i],result[j]]=[result[j],result[i]];
    }
    return result;
  };
  return [...shuffle(preferred),...shuffle(fallback)];
}
