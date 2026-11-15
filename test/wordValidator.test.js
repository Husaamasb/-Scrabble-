import { readFileSync } from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createWiktionaryValidator, validateWords } from '../src/game/wordValidator.js';

test('Wiktionary validator requests exact Arabic and English entries', async()=>{
  const requests=[];
  const fetchMock=async url=>{requests.push(url);return {ok:true,json:async()=>({query:{pages:[{pageid:1,title:'word'}]}})};};
  const validator=createWiktionaryValidator(fetchMock);
  assert.equal(await validator({word:'book',language:'en'}),true);
  assert.equal(await validator({word:'كتاب',language:'ar'}),true);
  assert.match(requests[0],/en\.wiktionary\.org/);
  assert.match(requests[1],/ar\.wiktionary\.org/);
  assert.match(requests[1],/titles=%D9%83%D8%AA%D8%A7%D8%A8/);
});

test('missing dictionary entries are rejected',async()=>{
  const validator=createWiktionaryValidator(async()=>({ok:true,json:async()=>({query:{pages:[{ns:0,title:'notaword',missing:true}]}})}));
  assert.equal(await validator({word:'notaword',language:'en'}),false);
});

test('dictionary network failures never approve words',async()=>{
  const validator=createWiktionaryValidator(async()=>({ok:false,status:503}));
  const result=await validateWords([{letters:'book'}],'en',validator);
  assert.equal(result.valid,false);
  assert.equal(result.words[0].accepted,false);
  assert.equal(result.reason,'word-not-accepted');
});

test('server dictionary has a secret-backed AI fallback for missing Wiktionary entries',()=>{
  const source=readFileSync(new URL('../supabase/functions/scrabble-move/index.ts',import.meta.url),'utf8');
  assert.ok(source.includes('OPENAI_API_KEY'));
  assert.ok(source.includes('OPENAI_DICTIONARY_MODEL'));
  assert.ok(source.includes('api.openai.com/v1/responses'));
  assert.ok(source.includes('type: "json_schema"'));
  assert.ok(source.includes('store: false'));
  assert.ok(source.includes('if (!valid && openAiKey)'));
});
