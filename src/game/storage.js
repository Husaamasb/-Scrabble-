const STORAGE_KEY='scrabble:saved-games:v1';

function getStorage(storage){
  const target=storage ?? globalThis.localStorage;
  if(!target) throw new Error('Local storage is not available');
  return target;
}

function readAll(storage){
  const target=getStorage(storage);
  try{
    const value=JSON.parse(target.getItem(STORAGE_KEY)||'[]');
    return Array.isArray(value)?value.filter(item=>item&&typeof item.id==='string'&&item.session):[];
  }catch{return [];}
}

export function listSavedGames({language}={},storage){
  const games=readAll(storage).sort((a,b)=>b.updatedAt-a.updatedAt);
  return language?games.filter(game=>game.language===language):games;
}

export function saveGame(session,{id,title}={},storage){
  if(!session||!Array.isArray(session.players)||!session.board) throw new Error('Invalid game session');
  const target=getStorage(storage);
  const games=readAll(target);
  const gameId=id||`game-${Date.now()}-${Math.random().toString(36).slice(2,8)}`;
  const now=Date.now();
  const existing=games.find(game=>game.id===gameId);
  const record={id:gameId,title:title||`Scrabble ${session.language.toUpperCase()}`,language:session.language,
    status:session.status||'playing',updatedAt:now,createdAt:existing?.createdAt||now,session};
  const next=[record,...games.filter(game=>game.id!==gameId)];
  target.setItem(STORAGE_KEY,JSON.stringify(next));
  return record;
}

export function loadSavedGame(id,storage){
  return readAll(storage).find(game=>game.id===id)||null;
}

export function deleteSavedGame(id,storage){
  const target=getStorage(storage);
  const games=readAll(target);
  const next=games.filter(game=>game.id!==id);
  target.setItem(STORAGE_KEY,JSON.stringify(next));
  return next.length!==games.length;
}

export function exportSavedGames(storage){
  return JSON.stringify({format:'scrabble-saves-v1',games:readAll(storage)},null,2);
}

export function importSavedGames(serialized,storage){
  const parsed=typeof serialized==='string'?JSON.parse(serialized):serialized;
  if(parsed?.format!=='scrabble-saves-v1'||!Array.isArray(parsed.games)) throw new Error('Unsupported save format');
  const target=getStorage(storage);
  const existing=readAll(target);
  const merged=new Map(existing.map(game=>[game.id,game]));
  for(const game of parsed.games){
    if(!game||typeof game.id!=='string'||!game.session||!Array.isArray(game.session.players)) continue;
    merged.set(game.id,game);
  }
  const result=[...merged.values()].sort((a,b)=>b.updatedAt-a.updatedAt);
  target.setItem(STORAGE_KEY,JSON.stringify(result));
  return result.length;
}
