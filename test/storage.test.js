import test from 'node:test';
import assert from 'node:assert/strict';
import { listSavedGames, saveGame, loadSavedGame, deleteSavedGame, exportSavedGames, importSavedGames } from '../src/game/storage.js';

function memoryStorage(){
  const values=new Map();
  return {getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value),removeItem:key=>values.delete(key)};
}
const session=(language='en')=>({language,players:[{id:'p1'}],board:{},status:'playing'});

test('saved games can be created, listed, loaded, and deleted',()=>{
  const storage=memoryStorage();
  const saved=saveGame(session(),{id:'match-1',title:'Test match'},storage);
  assert.equal(saved.id,'match-1');
  assert.equal(listSavedGames({},storage).length,1);
  assert.equal(loadSavedGame('match-1',storage).title,'Test match');
  assert.equal(deleteSavedGame('match-1',storage),true);
  assert.equal(loadSavedGame('match-1',storage),null);
});

test('saved games can be filtered by language',()=>{
  const storage=memoryStorage();
  saveGame(session('en'),{id:'en-1'},storage);
  saveGame(session('ar'),{id:'ar-1'},storage);
  assert.equal(listSavedGames({language:'ar'},storage).length,1);
});

test('save export/import merges records and rejects unsupported formats',()=>{
  const first=memoryStorage(),second=memoryStorage();
  saveGame(session('ar'),{id:'backup-1'},first);
  const backup=exportSavedGames(first);
  assert.equal(importSavedGames(backup,second),1);
  assert.equal(loadSavedGame('backup-1',second).language,'ar');
  assert.throws(()=>importSavedGames('{"format":"wrong","games":[]}',second),/Unsupported/);
});
