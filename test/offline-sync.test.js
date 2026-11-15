import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { collectLocalSessions, mergeLocalAndCloudSessions } from '../src/cloud/localGameSync.js';

const schema = readFileSync(new URL('../supabase/schema.sql', import.meta.url), 'utf8');
const app = readFileSync(new URL('../src/App.jsx', import.meta.url), 'utf8');
const localTable = readFileSync(new URL('../src/LocalTable.jsx', import.meta.url), 'utf8');

function memoryStorage(entries = {}) {
  const values = new Map(Object.entries(entries));
  return {
    get length() { return values.size; },
    key(index) { return [...values.keys()][index] ?? null; },
    getItem(key) { return values.get(key) ?? null; },
    setItem(key, value) { values.set(key, String(value)); },
    removeItem(key) { values.delete(key); },
  };
}

const session = { players: [{ id: 'p1' }, { id: 'p2' }], board: {}, status: 'playing' };

test('local sessions are collected from Arabic and English local/bot save keys', () => {
  const storage = memoryStorage({
    'scrabble:local-session:ar:bot': JSON.stringify({ version: 1, session, updatedAt: '2026-11-15T10:00:00.000Z' }),
    'scrabble:local-session:en:local': JSON.stringify({ version: 1, session, updatedAt: '2026-11-15T11:00:00.000Z' }),
    'scrabble:local-session:invalid': JSON.stringify({ version: 1, session }),
  });
  const rows = collectLocalSessions(storage);
  assert.deepEqual(rows.map(row => row.game_key).sort(), ['ar:bot', 'en:local']);
});

test('sync merge uploads newer local sessions and downloads newer cloud sessions', () => {
  const local = [
    { game_key: 'ar:bot', updated_at: '2026-11-15T12:00:00.000Z', session },
    { game_key: 'en:local', updated_at: '2026-11-15T09:00:00.000Z', session },
    { game_key: 'ar:local', updated_at: '2026-11-15T08:00:00.000Z', session },
  ];
  const cloud = [
    { game_key: 'ar:bot', updated_at: '2026-11-15T11:00:00.000Z', session },
    { game_key: 'en:local', updated_at: '2026-11-15T10:00:00.000Z', session },
  ];
  const result = mergeLocalAndCloudSessions(local, cloud);
  assert.deepEqual(result.uploads.map(row => row.game_key).sort(), ['ar:bot', 'ar:local']);
  assert.deepEqual(result.downloads.map(row => row.game_key), ['en:local']);
});

test('offline game cloud saves are private to their owning authenticated account', () => {
  assert.ok(schema.includes('create table if not exists public.scrabble_saved_games'));
  assert.ok(schema.includes('alter table public.scrabble_saved_games enable row level security;'));
  assert.ok(schema.includes('using ((select auth.uid())=user_id)'));
  assert.ok(schema.includes('with check ((select auth.uid())=user_id)'));
  assert.ok(schema.includes('grant select,insert,update,delete on public.scrabble_saved_games to authenticated;'));
});

test('offline sessions sync at sign-in and when the browser comes back online', () => {
  assert.ok(app.includes('syncLocalSessionsToCloud(userId)'));
  assert.ok(app.includes("addEventListener?.('online',syncWhenOnline)"));
  assert.ok(app.includes('cloudSaveSyncReady'));
  assert.ok(localTable.includes('saveLocalGameToCloud(userId,language,botMode?\'bot\':\'local\',session,updatedAt)'));
  assert.ok(localTable.includes("'scrabble-saved-games-synced'"));
});
