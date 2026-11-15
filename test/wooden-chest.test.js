import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const local=readFileSync(new URL('../src/LocalTable.jsx',import.meta.url),'utf8');
const css=readFileSync(new URL('../src/styles.css',import.meta.url),'utf8');
test('wooden chest opens with a hinged lid and displays the active player rack in one row',()=>{
 assert.ok(local.includes('className="chest-panel"'));
 assert.ok(local.includes("className={'chest-lid '+(chestOpen?'open':'closed')}"));
 assert.ok(local.includes('player.rack.map(tile=>'));
 assert.ok(local.includes('className="chest-row"'));
 assert.ok(local.includes('session.bag.length'));
 assert.ok(css.includes('.chest-lid.open{transform:perspective(500px) rotateX(-48deg);'));
 assert.ok(css.includes('.chest-row{display:flex'));
 assert.ok(css.includes('.chest-tile.chosen{'));
});
test('chest tile selection is connected to board play and hides the bot rack',()=>{
 assert.ok(local.includes('selected===tile.id||exchange.includes(tile.id)'));
 assert.ok(local.includes('setSelected(current=>current===tile.id?null:tile.id)'));
 assert.ok(local.includes('placedIds.has(tile.id)'));
 assert.ok(local.includes('const humanTurn=!botMode||session.currentPlayer===0;'));
 assert.ok(local.includes('chestOpen&&humanTurn'));
 assert.ok(local.includes("session.status==='playing'&&humanTurn"));
});
