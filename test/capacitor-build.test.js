import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const vite = readFileSync(new URL('../vite.config.js', import.meta.url), 'utf8');
const android = readFileSync(new URL('../.github/workflows/android-debug.yml', import.meta.url), 'utf8');
const ios = readFileSync(new URL('../.github/workflows/ios-simulator.yml', import.meta.url), 'utf8');
const icons = readFileSync(new URL('../scripts/generate-native-icons.py', import.meta.url), 'utf8');

test('Capacitor builds use relative asset paths instead of GitHub Pages paths', () => {
  assert.match(vite, /CAPACITOR_BUILD === 'true'[\s\S]*?'\.\/'/);
  assert.match(android, /CAPACITOR_BUILD=true npm run build/);
  assert.match(ios, /CAPACITOR_BUILD=true npm run build/);
});

test('native launcher icons are generated from the original Scrabble logo', () => {
  assert.match(icons, /public.*logo-original\.webp/);
  assert.match(icons, /ic_launcher\.png/);
  assert.match(icons, /ic_launcher_foreground\.png/);
  assert.match(icons, /AppIcon-1024\.png/);
});
