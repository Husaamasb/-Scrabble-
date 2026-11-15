import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const schema = readFileSync(new URL('../supabase/schema.sql', import.meta.url), 'utf8');
const cloud = readFileSync(new URL('../src/CloudDashboard.jsx', import.meta.url), 'utf8');
const dashboard = readFileSync(new URL('../src/Dashboard.jsx', import.meta.url), 'utf8');

test('tournaments have RLS-protected tables and explicit read grants', () => {
  for (const table of ['scrabble_tournaments','scrabble_tournament_players','scrabble_tournament_matches']) {
    assert.match(schema, new RegExp('alter table public\\.' + table + ' enable row level security'));
    assert.match(schema, new RegExp('create policy "[^"]+" on public\\.' + table + ' for select to authenticated'));
  }
  assert.match(schema, /grant select on public\.scrabble_tournaments,public\.scrabble_tournament_players,public\.scrabble_tournament_matches to authenticated/);
});

test('tournament RPCs restrict execution and validate host ownership', () => {
  for (const fn of ['create_scrabble_tournament','join_scrabble_tournament','start_scrabble_tournament','report_scrabble_tournament_match']) {
    assert.match(schema, new RegExp('revoke all on function public\\.' + fn + '\\('));
    assert.match(schema, new RegExp('grant execute on function public\\.' + fn + '\\('));
  }
  assert.match(schema, /target\.owner_id<>auth\.uid\(\)/);
  assert.match(schema, /t\.owner_id<>auth\.uid\(\)/);
  assert.match(schema, /winning_player<>m\.player1_id and winning_player<>m\.player2_id/);
});

test('single-elimination bracket advances winners and handles byes', () => {
  assert.match(schema, /round_size integer:=1/);
  assert.match(schema, /if p1 is null and p2 is null then continue/);
  assert.match(schema, /winner_id,status/);
  assert.match(schema, /next_round:=m\.round_number\+1/);
  assert.match(schema, /champion_id=winners\[1\]/);
});

test('tournament UI is connected to authenticated cloud dashboard', () => {
  assert.match(dashboard, /'tournaments'\]/);
  assert.match(cloud, /section==='tournaments'/);
  for (const rpc of ['create_scrabble_tournament','join_scrabble_tournament','start_scrabble_tournament','report_scrabble_tournament_match']) {
    assert.ok(cloud.includes("rpc('" + rpc + "'"), rpc + ' must be called from the UI');
  }
  assert.match(cloud, /cloud-tournament-round/);
});
