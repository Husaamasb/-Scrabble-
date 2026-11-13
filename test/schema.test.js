import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const schema = readFileSync(new URL('../supabase/schema.sql', import.meta.url), 'utf8');

test('private rack table exists before its realtime publication registration', () => {
  const table = schema.indexOf('create table if not exists public.room_player_private');
  const publication = schema.indexOf('alter publication supabase_realtime add table public.room_player_private');
  assert.notEqual(table, -1);
  assert.notEqual(publication, -1);
  assert.ok(table < publication, 'the table must be created before publication registration');
});

test('realtime SQL blocks use valid dollar delimiters', () => {
  assert.doesNotMatch(schema, /^\s*do\s+\$(?!\$)/m);
  assert.doesNotMatch(schema, /^\s*end\s+\$(?!\$)/m);
  const starts = schema.match(/^\s*do\s+\$\$/gm) || [];
  const ends = schema.match(/^\s*end\s+\$\$;/gm) || [];
  assert.equal(starts.length, ends.length);
});

test('private racks remain protected from direct client writes', () => {
  assert.match(schema, /alter table public\.room_player_private enable row level security/);
  assert.match(schema, /revoke all on public\.room_player_private from anon, authenticated/);
  assert.match(schema, /grant select on public\.room_player_private to authenticated/);
});
