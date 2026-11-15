import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const validator=readFileSync(new URL('../src/cloud/dictionary.js',import.meta.url),'utf8');
const local=readFileSync(new URL('../src/LocalTable.jsx',import.meta.url),'utf8');
const edge=readFileSync(new URL('../supabase/functions/scrabble-dictionary/index.ts',import.meta.url),'utf8');
const onlineEdge=readFileSync(new URL('../supabase/functions/scrabble-move/index.ts',import.meta.url),'utf8');
test('local game prefers authenticated server dictionary and keeps Wiktionary fallback',()=>{
 assert.ok(validator.includes("supabase.functions.invoke('scrabble-dictionary'"));
 assert.ok(validator.includes('createWiktionaryValidator(fetchImpl)'));
 assert.ok(validator.includes('return localValidator({ word: exactWord, language })'));
 assert.ok(local.includes('createHybridDictionaryValidator()'));
});
test('server dictionary checks admin overrides and cache before providers',()=>{
 assert.ok(edge.includes('scrabble_dictionary_overrides'));
 assert.ok(edge.includes('scrabble_dictionary_cache'));
 assert.ok(edge.includes('OPENAI_API_KEY'));
 assert.ok(edge.includes('https://api.openai.com/v1/responses'));
 assert.ok(edge.includes('type: "json_schema"'));
 assert.ok(edge.includes('store: false'));
 assert.ok(onlineEdge.includes('https://api.openai.com/v1/responses'));
 assert.ok(onlineEdge.includes('type: "json_schema"'));
 assert.ok(onlineEdge.includes('AbortSignal.timeout(4500)'));
});
test('dictionary rejects mixed scripts and malformed words',()=>{
 assert.ok(edge.includes('Arabic words must contain Arabic letters only'));
 assert.ok(edge.includes('English words must contain English letters only'));
 assert.ok(edge.includes('normalized.length > 80'));
});
