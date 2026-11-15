import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const local=readFileSync(new URL('../src/LocalTable.jsx',import.meta.url),'utf8');
const css=readFileSync(new URL('../src/styles.css',import.meta.url),'utf8');
test('wooden chest opens with a hinged lid and displays one shuffled row',()=>{
 assert.ok(local.includes('className="chest-panel"'));
 assert.ok(local.includes("className={'chest-lid '+(chestOpen?'open':'closed')}"));
 assert.ok(local.includes('session.bag.slice(0,7)'));
 assert.ok(local.includes('className="chest-row"'));
 assert.ok(local.includes('session.bag.length'));
 assert.ok(css.includes('.chest-lid.open{transform:perspective(500px) rotateX(-48deg);'));
 assert.ok(css.includes('.chest-row{display:flex'));
});
test('chest tiles flip one at a time and reveal the next face',()=>{
 assert.ok(local.includes('chestFlipId===tileId'));
 assert.ok(local.includes("setChestFlipId(current=>current===tileId?null:tileId)"));
 assert.ok(local.includes('face-down'));
 assert.ok(local.includes('flipped'));
 assert.ok(css.includes('.chest-tile.face-down'));
 assert.ok(css.includes('.chest-tile.flipped'));
});
