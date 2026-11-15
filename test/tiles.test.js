import test from 'node:test';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { TILE_SETS, tileSetReport, createTileBag, drawTiles, exchangeTiles, settleEndgame } from '../src/game/tiles.js';


test('English tile set matches the specified 100 tiles',()=>{
  assert.equal(tileSetReport('en').actualTotal,100);
  assert.equal(createTileBag('en',()=>0.5).length,100);
});

test('Arabic tile table matches the exact 108-piece distribution in the user-supplied table',()=>{
  const report=tileSetReport('ar');
  assert.equal(report.declaredTotal,108);
  assert.equal(report.actualTotal,108);
  assert.equal(report.ready,true);
  assert.equal(createTileBag('ar',()=>0.5).length,108);
  assert.deepEqual(TILE_SETS.ar.tiles,[
    ['ا',1,8],
    ['أ',1,2],
    ['إ',1,2],
    ['آ',8,1],
    ['ب',1,4],
    ['ت',1,4],
    ['ة',5,1],
    ['ث',1,3],
    ['ج',1,3],
    ['ح',1,3],
    ['خ',1,3],
    ['د',1,3],
    ['ذ',1,3],
    ['ر',2,3],
    ['ز',2,3],
    ['س',1,3],
    ['ش',2,3],
    ['ص',2,3],
    ['ض',3,3],
    ['ط',2,2],
    ['ظ',4,2],
    ['ع',2,3],
    ['غ',4,3],
    ['ف',1,3],
    ['ق',2,3],
    ['ك',3,3],
    ['ل',1,3],
    ['لا',2,2],
    ['لأ',3,1],
    ['لآ',3,1],
    ['لإ',3,1],
    ['م',1,4],
    ['ن',1,3],
    ['ه',1,3],
    ['و',1,3],
    ['ؤ',10,1],
    ['ي',1,3],
    ['ى',3,1],
    ['ء',8,1],
    ['ئ أول الكلمة',10,2],
    ['★',0,2]
  ]);
  assert.deepEqual(TILE_SETS.ar.tiles.find(row=>row[0]==='س'),['س',1,3]);
  assert.deepEqual(TILE_SETS.ar.tiles.find(row=>row[0]==='ش'),['ش',2,3]);
  assert.equal(TILE_SETS.ar.tiles.some(row=>row[0]==='يء'||row[0]==='ئ'),false);
});
test('Supabase server distributions exactly match the browser tile tables',()=>{
  const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
  const languageBlocks=schema.match(/if target\.language='en' then([\s\S]*?)elsif target\.language='ar' then([\s\S]*?)else\s+raise exception 'Unsupported room language'/);
  assert.ok(languageBlocks,'server tile distribution branches must exist');
  const extract=block=>[...block.matchAll(/\('([^']+)',\s*(\d+),\s*(\d+)\)/g)]
    .map(match=>[match[1],Number(match[2]),Number(match[3])]);
  for(const [index,language] of ['en','ar'].entries()){
    assert.deepEqual(extract(languageBlocks[index+1]),TILE_SETS[language].tiles,
      `Supabase ${language} distribution must match the app's exact tile table`);
  }
});


test('wooden chest tiles stay in one horizontal row and reveal on tap in local and online games',()=>{
  const local=readFileSync(new URL('../src/LocalTable.jsx',import.meta.url),'utf8');
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  const styles=readFileSync(new URL('../src/styles.css',import.meta.url),'utf8');
  for(const source of [local,cloud]){
    assert.ok(source.includes("'face-down'"),'unrevealed tiles must show their backs');
    assert.ok(source.includes("'revealed'"),'revealed tiles must show their faces');
    assert.ok(source.includes("'؟'"),'the back must not expose the letter');
    assert.ok(source.includes('setRevealed'),'tapping a tile must reveal it');
  }
  assert.ok(styles.includes('.chest-row{display:flex;gap:8px;overflow-x:auto'));
  assert.ok(styles.includes('.cloud-rack-tiles{display:flex;gap:8px;flex-wrap:nowrap;overflow-x:auto'));
});

test('draw returns the requested number and leaves the rest in the bag',()=>{
  const bag=createTileBag('en',()=>0.25);
  const result=drawTiles(bag,7);
  assert.equal(result.drawn.length,7);
  assert.equal(result.remaining.length,93);
});

test('exchange requires enough bag tiles and replaces exactly selected count',()=>{
  const bag=createTileBag('en',()=>0.25);
  const result=exchangeTiles(bag,[{letter:'A'},{letter:'B'}],()=>0.5);
  assert.equal(result.valid,true);
  assert.equal(result.replacements.length,2);
  assert.equal(result.remaining.length,100);
  assert.ok(result.remaining.some(tile=>tile.letter==='A'));
  assert.ok(result.remaining.some(tile=>tile.letter==='B'));
  assert.equal(exchangeTiles([{}],[{},{}]).reason,'not-enough-tiles-in-bag');
});

test('endgame subtracts opponents leftover tiles and awards them to finisher',()=>{
  const scores=settleEndgame([40,35],[[{points:2},{points:3}],[{points:4}]],0);
  assert.deepEqual(scores,[44,31]);
});

test('cloud private racks remain read-only to browser clients',()=>{
  const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
  assert.ok(schema.includes('create policy "players read only their private room state"'));
  assert.ok(schema.includes('using(user_id=auth.uid() and public.is_scrabble_room_member(room_id))'));
  assert.ok(schema.includes('revoke all on public.room_player_private from anon, authenticated;'));
  assert.ok(schema.includes('grant select on public.room_player_private to authenticated;'));
  assert.ok(!schema.includes('grant insert on public.room_player_private'));
  assert.ok(!schema.includes('grant update on public.room_player_private'));
});

test('server tile bag stays inaccessible to browser clients',()=>{
  const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
  assert.ok(schema.includes('alter table public.room_tile_bag enable row level security;'));
  assert.ok(schema.includes('revoke all on public.room_tile_bag from public, anon, authenticated;'));
  assert.ok(!schema.includes('grant select on public.room_tile_bag'));
});

test('generic client turn submission remains disabled until authoritative validation exists',()=>{
  const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
  const fn=schema.indexOf('create or replace function public.submit_scrabble_turn(');
  const revoke=schema.indexOf('revoke execute on function public.submit_scrabble_turn(uuid,integer,jsonb,jsonb) from public, anon, authenticated;');
  assert.ok(fn>=0&&revoke>fn);
  assert.ok(schema.slice(fn,revoke).includes('security definer'));
});

test('cloud match initialization creates the tile bag and private racks on the server',()=>{
  const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
  const fn=schema.lastIndexOf('create or replace function public.start_scrabble_room(target_room uuid)');
  const start=schema.slice(fn);
  assert.ok(fn>=0);
  assert.ok(start.startsWith('create or replace function public.start_scrabble_room(target_room uuid)'));
  assert.ok(start.includes('insert into public.room_player_private(room_id,user_id,private_state)'));
  assert.ok(start.includes('insert into public.room_tile_bag(room_id,position,tile)'));
});

 
test('pass turn is server-authoritative and accepts no client game-state payload',()=>{
  const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
  const fn=schema.lastIndexOf('create or replace function public.pass_scrabble_turn(');
  const end=schema.indexOf(String.fromCharCode(36).repeat(2)+';',fn);
  assert.ok(fn>=0&&end>fn);
  const body=schema.slice(fn,end);
  assert.ok(body.includes('for update'));
  assert.ok(body.includes('expected_revision'));
  assert.ok(body.includes('It is not your turn'));
  assert.ok(body.includes('is_withdrawn'));
  assert.ok(body.includes("'consecutive_passes'"));
  assert.ok(body.includes("'revision',expected_revision+1"));
  assert.ok(!body.includes('public_state'));
  assert.ok(schema.includes('grant execute on function public.pass_scrabble_turn(uuid,integer) to authenticated;'));
});

test('cloud tile exchange is server-authoritative and updates only the caller private rack',()=>{
  const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
  const fn=schema.lastIndexOf('create or replace function public.exchange_scrabble_tiles(');
  const end=schema.indexOf('$exchange$;',fn);
  assert.ok(fn>=0&&end>fn);
  const body=schema.slice(fn,end);
  for(const required of ['for update','expected_revision','It is not your turn','is_withdrawn','room_player_private','room_tile_bag','jsonb_array_elements','remaining_tiles','revision','order by random()',"'type','exchange'"]) assert.ok(body.includes(required),required);
  assert.ok(body.includes('Choose between 1 and 7 tiles'));
  assert.ok(body.includes('A selected tile is not in your rack'));
  assert.ok(body.includes('bag_count < 7'));
  assert.ok(schema.includes('grant execute on function public.exchange_scrabble_tiles(uuid,integer,uuid[]) to authenticated;'));
  assert.ok(schema.includes('revoke all on function public.exchange_scrabble_tiles(uuid,integer,uuid[]) from public, anon;'));
});


test('cloud rack selection is disabled outside the current player turn',()=>{
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes("activeRoom.game_state?.player_ids?.[Number(activeRoom.game_state?.turn_index)]!==user.id"));
  assert.ok(cloud.includes("useEffect(()=>{setSelectedExchangeTiles([]);setSelectedPlacementTileId(null);setPendingPlacements([]);setBlankAs('');setExchangeMode(false);setRevealedRackTiles(new Set());},[activeRoom?.id,activeRoom?.status,activeRoom?.game_state?.revision]);"));
});
