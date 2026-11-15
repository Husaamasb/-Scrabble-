import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const cloud = readFileSync(new URL('../src/CloudDashboard.jsx', import.meta.url), 'utf8');
const schema = readFileSync(new URL('../supabase/schema.sql', import.meta.url), 'utf8');

test('quick matchmaking joins a public two-player queue for the selected language', () => {
  assert.ok(cloud.includes("eq('name','Quick match')"));
  assert.ok(cloud.includes(".eq('is_public',true).eq('status','waiting').eq('language',language)"));
  assert.ok(cloud.includes("rpc('join_room_by_code'"));
  assert.ok(cloud.includes("rpc('set_scrabble_ready'"));
  assert.ok(cloud.includes("room_name:'Quick match',public_room:true,player_limit:2"));
  assert.ok(cloud.includes("setQuickMatchMode(true)"));
  assert.ok(cloud.includes("activeMembers.length!==2||activeMembers.some(member=>!member.is_ready)"));
  assert.ok(cloud.includes("rpc('start_scrabble_room'"));
  assert.ok(cloud.includes("ar?'العب مباراة سريعة':'Quick match'"));
});

test('quick matchmaking relies on the server-enforced public room capacity and host checks', () => {
  assert.ok(schema.includes("if player_limit not between 2 and 4 then raise exception 'Player limit must be 2 to 4';"));
  assert.ok(schema.includes("if target.host_id <> auth.uid() then raise exception 'Only the host can start the match';"));
  assert.ok(schema.includes("if next_seat > target.max_players then"));
});
