import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('web app manifest is valid and installable',async()=>{
  const manifest=JSON.parse(await readFile(new URL('../public/manifest.webmanifest',import.meta.url),'utf8'));
  assert.equal(manifest.name,'Scrabble');
  assert.equal(manifest.display,'standalone');
  assert.equal(manifest.start_url,'/');
});

test('offline service worker handles navigation fallback',async()=>{
  const source=await readFile(new URL('../public/sw.js',import.meta.url),'utf8');
  assert.match(source,/addEventListener\('fetch'/);
  assert.match(source,/caches\.match\('\/'\)/);
});
