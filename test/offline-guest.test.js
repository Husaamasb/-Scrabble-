import test from 'node:test';
import assert from 'node:assert/strict';
import { createWiktionaryValidator } from '../src/game/wordValidator.js';
import { OFFLINE_WORDS } from '../src/game/bot.js';
import { readFileSync } from 'node:fs';

test('guest mode is available without a cloud account and bypasses the auth gate for local play',()=>{
  const app=readFileSync(new URL('../src/App.jsx',import.meta.url),'utf8');
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(app.includes('onGuestPlay={()=>setGuestMode(true)}'));
  assert.ok(app.indexOf('if(localMode)return <LocalTable')<app.indexOf('if((!authSession?.user&&!guestMode)||authRecovery)'));
  assert.ok(app.includes('{!guestMode&&<><nav className="bottom-nav"'));
  assert.ok(cloud.includes('onGuestPlay?.()'));
});

test('offline dictionary accepts bundled exact words when no network fetch exists',async()=>{
  const validate=createWiktionaryValidator(undefined);
  assert.equal(await validate({word:'cat',language:'en'}),true);
  assert.equal(await validate({word:'كتاب',language:'ar'}),true);
  assert.equal(await validate({word:'notaword',language:'en'}),false);
  assert.equal(OFFLINE_WORDS.en.has('cat'),true);
});

test('offline dictionary falls back to bundled words only after a network failure',async()=>{
  const validate=createWiktionaryValidator(async()=>{throw new Error('offline');});
  assert.equal(await validate({word:'cat',language:'en'}),true);
  await assert.rejects(()=>validate({word:'notaword',language:'en'}),/offline/);
});

test('online dictionary still rejects words missing from Wiktionary rather than overriding a negative verdict',async()=>{
  const validate=createWiktionaryValidator(async()=>({ok:true,json:async()=>({query:{pages:[{ns:0,title:'notaword',missing:true}]}})}));
  assert.equal(await validate({word:'notaword',language:'en'}),false);
});
