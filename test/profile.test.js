import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');

test('signed-in profile displays the current friend count',()=>{
  assert.ok(cloud.includes('<small>{t.friends}</small><b>{friends.length}</b>'));
});
