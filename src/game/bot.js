/** Order candidate moves according to the selected bot skill.
 * Moves are expected to be sorted from highest to lowest score.
 * Easier levels explore a wider range; harder levels focus on stronger moves.
 */
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
