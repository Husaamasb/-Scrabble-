import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('web app manifest is valid and installable from a project subpath',async()=>{
  const manifest=JSON.parse(await readFile(new URL('../public/manifest.webmanifest',import.meta.url),'utf8'));
  assert.equal(manifest.name,'Scrabble');
  assert.equal(manifest.display,'standalone');
  assert.equal(manifest.start_url,'./');
  assert.equal(manifest.scope,'./');
  assert.equal(manifest.icons[0].src,'./icon.svg');
});

test('service worker registers under the Vite base path',async()=>{
  const source=await readFile(new URL('../src/registerServiceWorker.js',import.meta.url),'utf8');
  assert.match(source,/import\.meta\.env\.BASE_URL/);
  assert.match(source,/scope: baseUrl\.pathname/);
});

test('offline service worker caches and restores the app within its own scope',async()=>{
  const source=await readFile(new URL('../public/sw.js',import.meta.url),'utf8');
  assert.match(source,/addEventListener\('fetch'/);
  assert.match(source,/self\.registration\.scope/);
  assert.match(source,/caches\.match\(APP_URL\)/);
  assert.match(source,/new URL\('manifest\.webmanifest',BASE_URL\)/);
});
