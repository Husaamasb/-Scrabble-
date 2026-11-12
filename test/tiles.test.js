import test from 'node:test';
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
  assert.ok(TILE_SETS.ar.tiles.some(row=>row[0]==='ئ شكل آخر'));
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
