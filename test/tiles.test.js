import test from 'node:test';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { TILE_SETS, tileSetReport, createTileBag, drawTiles, exchangeTiles, settleEndgame } from '../src/game/tiles.js';


test('English tile set matches the specified 100 tiles',()=>{
  assert.equal(tileSetReport('en').actualTotal,100);
  assert.equal(createTileBag('en',()=>0.5).length,100);
});

test('Arabic tile table is preserved without silently changing the unresolved total',()=>{
  const report=tileSetReport('ar');
  assert.equal(report.declaredTotal,110);
  assert.equal(report.actualTotal,110);
  assert.equal(report.ready,true);
  assert.equal(createTileBag('ar',()=>0.5).length,110);
  assert.ok(TILE_SETS.ar.tiles.some(row=>row[0]==='ئ أول الكلمة'));
  assert.ok(TILE_SETS.ar.tiles.some(row=>row[0]==='ئ'));
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
  assert.match(schema,/create policy "players read only their private room state"[\\s\\S]*?using\\s*\\(\\s*user_id\\s*=\\s*auth\\.uid\\(\\)\\s+and\\s+public\\.is_scrabble_room_member\\(room_id\\)\\s*\\)/i);
  assert.match(schema,/revoke all on public\\.room_player_private from anon, authenticated;/i);
  assert.match(schema,/grant select on public\\.room_player_private to authenticated;/i);
  assert.doesNotMatch(schema,/grant\\s+(?:insert|update|all)[^;]*on\\s+public\\.room_player_private\\s+to\\s+(?:anon|authenticated)/i);
});

test('server tile bag stays inaccessible to browser clients',()=>{
  const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
  assert.match(schema,/create table if not exists public\\.room_tile_bag[\\s\\S]*?alter table public\\.room_tile_bag enable row level security;[\\s\\S]*?revoke all on public\\.room_tile_bag from public, anon, authenticated;/i);
  assert.doesNotMatch(schema,/grant\\s+[^;]*on\\s+public\\.room_tile_bag\\s+to\\s+(?:anon|authenticated)/i);
});

test('generic client turn submission remains disabled until authoritative validation exists',()=>{
  const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
  assert.match(schema,/create or replace function public\\.submit_scrabble_turn\\([\\s\\S]*?security definer[\\s\\S]*?end;\\s*\\$\\$;\\s*-- Keep turn submission disabled[\\s\\S]*?revoke execute on function public\\.submit_scrabble_turn\\(uuid,integer,jsonb,jsonb\\) from public, anon, authenticated;/i);
});

test('cloud match initialization creates the tile bag and private racks on the server',()=>{
  const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
  const start=schema.slice(schema.lastIndexOf('create or replace function public.start_scrabble_room'));
  const signature=start.slice(0,start.indexOf('as $$'));
  assert.match(signature,/start_scrabble_room\\(target_room uuid\\)/i);
  assert.doesNotMatch(signature,/jsonb|rack|tiles/i);
  assert.match(start,/insert into public\\.room_player_private\\(room_id,user_id,private_state\\)/i);
  assert.match(start,/insert into public\\.room_tile_bag\\(room_id,position,tile\\)/i);
});
