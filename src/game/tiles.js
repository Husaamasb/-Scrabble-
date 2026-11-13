export const TILE_SETS = Object.freeze({
  en: {
    status: 'verified-from-user-table',
    declaredTotal: 100,
    tiles: [
      ['A',1,9],['B',3,2],['C',3,2],['D',2,4],['E',1,12],['F',4,2],
      ['G',2,3],['H',4,2],['I',1,9],['J',8,1],['K',5,1],['L',1,4],
      ['M',3,2],['N',1,6],['O',1,8],['P',3,2],['Q',10,1],['R',1,6],
      ['S',1,4],['T',1,6],['U',1,4],['V',4,2],['W',4,2],['X',8,1],
      ['Y',4,2],['Z',10,1],['★',0,2]
    ]
  },
  ar: {
    status: 'verified-from-user-table',
    declaredTotal: 110,
    tiles: [
      ['ا',1,8],['إ',1,2],['أ',1,2],['آ',8,1],['ب',1,4],['ج',1,3],
      ['ح',1,3],['خ',1,3],['د',1,3],['ذ',1,3],['ش',2,3],['ص',2,3],
      ['ض',3,3],['ط',2,2],['ظ',4,2],['ق',2,3],['ك',3,3],['ل',1,3],
      ['لا',2,2],['لإ',3,1],['ن',1,3],['ه',1,3],['و',1,3],['ؤ',10,1],
      ['ي',1,3],['ء',8,1],['ئ أول الكلمة',10,2],['★',0,2],['ت',1,4],
      ['ة',5,1],['ث',1,3],['ر',1,3],['ز',2,3],['س',1,3],['ع',2,3],
      ['غ',4,3],['ف',1,3],['لأ',3,1],['لآ',3,1],['م',1,4],['يء',5,1],
      ['ى',3,1],['ئ',8,1]
    ]
  }
});

export function tileSetReport(language) {
  const set=TILE_SETS[language];
  if (!set) throw new Error('Unsupported language');
  const actualTotal=set.tiles.reduce((sum,row)=>sum+row[2],0);
  return {
    language,
    declaredTotal:set.declaredTotal,
    actualTotal,
    matchesDeclaredTotal:actualTotal===set.declaredTotal,
    ready:set.status==='verified-from-user-table' && actualTotal===set.declaredTotal
  };
}

export function createTileBag(language, random=Math.random) {
  const report=tileSetReport(language);
  if (!TILE_SETS[language]) throw new Error('Unsupported language');
  // Preserve the exact supplied distribution; report mismatches instead of inventing tiles.
  const bag=[];
  for (const [letter,points,count] of TILE_SETS[language].tiles) {
    for(let i=0;i<count;i++) bag.push({letter,points,isBlank:letter==='★'});
  }
  for(let i=bag.length-1;i>0;i--){
    const j=Math.floor(random()*(i+1));
    [bag[i],bag[j]]=[bag[j],bag[i]];
  }
  return bag;
}

export function drawTiles(bag, amount) {
  const count=Math.max(0,Math.min(Math.floor(amount),bag.length));
  return { drawn:bag.slice(0,count), remaining:bag.slice(count) };
}

export function exchangeTiles(bag, selectedTiles, random=Math.random) {
  if (!Array.isArray(selectedTiles) || selectedTiles.length===0) return { valid:false, reason:'no-tiles-selected' };
  if (bag.length<selectedTiles.length) return { valid:false, reason:'not-enough-tiles-in-bag' };
  const shuffled=[...bag];
  const shuffle=items=>{
    for(let i=items.length-1;i>0;i--){
      const j=Math.floor(random()*(i+1));
      [items[i],items[j]]=[items[j],items[i]];
    }
    return items;
  };
  shuffle(shuffled);
  const replacements=shuffled.slice(0,selectedTiles.length);
  const remaining=shuffle([...shuffled.slice(selectedTiles.length),...selectedTiles]);
  return { valid:true, replacements, remaining, returned:selectedTiles };
}

export function settleEndgame(scores, racks, finisherIndex) {
  if (!Array.isArray(scores)||!Array.isArray(racks)||scores.length!==racks.length||
      !Number.isInteger(finisherIndex)||finisherIndex<0||finisherIndex>=scores.length) {
    throw new Error('Invalid endgame input');
  }
  const penalties=racks.map(rack=>rack.reduce((sum,tile)=>sum+(Number(tile.points)||0),0));
  const next=[...scores];
  penalties.forEach((penalty,index)=>{
    if(index===finisherIndex) return;
    next[index]-=penalty;
    next[finisherIndex]+=penalty;
  });
  return next;
}
