import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');

test('signed-in profile displays the current friend count',()=>{
  assert.ok(cloud.includes('<small>{t.friends}</small><b>{friends.length}</b>'));
});

test('profile avatar preview and picker reflect and persist the selected avatar',()=>{
  assert.ok(cloud.includes('cloud-profile-avatar-preview'));
  assert.ok(cloud.includes("profile?.avatar_url?.startsWith('emoji:')"));
  assert.ok(cloud.includes("avatar_url:'emoji:'+avatar"));
  assert.ok(cloud.includes("avatar_url:profile.avatar_url||'emoji:😀'"));
});

test('profile achievements unlock from server-backed wins, XP, and friend totals',()=>{
  for(const marker of ["id:'firstWin',ok:(profile?.wins||0)>=1","id:'tenWins',ok:(profile?.wins||0)>=10","id:'fiftyWins',ok:(profile?.wins||0)>=50","id:'xpThousand',ok:(profile?.xp||0)>=1000","id:'friendsTen',ok:friends.length>=10"]) assert.ok(cloud.includes(marker),marker);
  assert.ok(cloud.includes('cloud-achievement-list'));
});
