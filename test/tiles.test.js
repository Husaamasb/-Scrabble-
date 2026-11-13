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
  const languageBlocks=schema.match(/if target\\.language='en' then([\\s\\S]*?)elsif target\\.language='ar' then([\\s\\S]*?)else\\s+raise exception 'Unsupported room language'/);
  assert.ok(languageBlocks,'server tile distribution branches must exist');
  const extract=block=>[...block.matchAll(/\\('([^']+)',\\s*(\\d+),\\s*(\\d+)\\)/g)]
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
