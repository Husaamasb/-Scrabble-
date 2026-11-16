import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
const sound=readFileSync(new URL('../src/game/sound.js',import.meta.url),'utf8');
const app=readFileSync(new URL('../src/App.jsx',import.meta.url),'utf8');

test('cloud settings initialize sound and notification preferences before rendering controls',()=>{
  assert.ok(cloud.includes('const [soundEnabled,setSoundEnabled]=useState(false)'));
  assert.ok(cloud.includes('[preferences,setPreferences]=useState('));
  assert.ok(cloud.includes('setPreferences(current=>({...current,...(data.notification_preferences||{})}))'));
  assert.ok(cloud.includes("localStorage?.setItem('scrabble:sound-enabled',String(Boolean(data.sound_enabled)))"));
  assert.ok(cloud.includes('onClick={saveUserSettings}'));
});

test('accepted valid words can play the optional locally generated sound',()=>{
  assert.ok(app.includes("import { playWordAcceptedSound } from './game/sound.js'"));
  assert.ok(app.includes('playWordAcceptedSound();'));
  assert.ok(sound.includes("getItem('scrabble:sound-enabled') !== 'true'"));
  assert.ok(sound.includes('AudioContextClass'));
  assert.ok(sound.includes('oscillator.start'));
});
