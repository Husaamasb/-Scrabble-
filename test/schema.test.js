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

 
test('period leaderboards aggregate XP without exposing private match history',()=>{
  assert.ok(schema.includes('create table if not exists public.scrabble_leaderboard_periods'));
  assert.ok(schema.includes('alter table public.scrabble_leaderboard_periods enable row level security'));
  assert.ok(schema.includes('create policy "public leaderboard aggregates visible"'));
  assert.ok(schema.includes("p.privacy='everyone'"));
  assert.ok(schema.includes('create trigger aggregate_scrabble_leaderboard_periods'));
  assert.ok(schema.includes('revoke all on function public.aggregate_scrabble_leaderboard_periods()'));
  assert.ok(schema.includes("date_trunc('week',new.created_at at time zone 'UTC')"));
  assert.ok(schema.includes("date_trunc('month',new.created_at at time zone 'UTC')"));
});

test('online leaderboard offers global, weekly, monthly, and language-specific views',()=>{
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  for(const key of ["['global',t.leaderboardGlobal]","['weekly',t.leaderboardWeekly]","['monthly',t.leaderboardMonthly]","['ar',t.leaderboardArabic]","['en',t.leaderboardEnglish]"]) assert.ok(cloud.includes(key),key);
  assert.ok(cloud.includes("supabase.from('scrabble_leaderboard_periods')"));
  assert.ok(cloud.includes(".eq('privacy','everyone')"));
  assert.ok(cloud.includes("periodStart='0001-01-01'"));
});

 
test('iOS simulator workflow builds the Capacitor app on macOS without claiming an IPA',()=>{
  const workflow=readFileSync(new URL('../.github/workflows/ios-simulator.yml',import.meta.url),'utf8');
  assert.match(workflow,/runs-on: macos-15/);
  assert.match(workflow,/npx cap add ios/);
  assert.match(workflow,/npx cap sync ios/);
  assert.match(workflow,/xcodebuild/);
  assert.match(workflow,/CODE_SIGNING_ALLOWED=NO/);
  assert.match(workflow,/Scrabble-iOS-Simulator\.zip/);
  assert.match(workflow,/actions\/upload-artifact@v4/);
  const readme=readFileSync(new URL('../README.md',import.meta.url),'utf8');
  assert.match(readme,/unsigned simulator app/);
});

test('authoritative online move RPC and dictionary cache are included in the reproducible schema',()=>{
  assert.ok(schema.includes('create table if not exists public.scrabble_dictionary_cache'));
  assert.ok(schema.includes('alter table public.scrabble_dictionary_cache enable row level security'));
  assert.match(schema,/create or replace function public\.place_scrabble_word/i);
  assert.ok(schema.includes("revoke all on function public.place_scrabble_word(uuid,integer,jsonb,jsonb,uuid) from public,anon,authenticated"));
  assert.ok(schema.includes("grant execute on function public.place_scrabble_word(uuid,integer,jsonb,jsonb,uuid) to service_role"));
});

test('online presence uses one shared realtime channel for all signed-in players',()=>{
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes("supabase.channel('scrabble:online',{config:{presence:{key:user.id}}})"));
  assert.ok(cloud.includes("p.user_id!==user.id"));
});


test('daily challenges are driven by server match results and claim XP through an authenticated RPC',()=>{
  assert.ok(schema.includes('create table if not exists public.scrabble_daily_challenge_progress'));
  assert.ok(schema.includes('create trigger track_scrabble_daily_challenges'));
  assert.ok(schema.includes("case when new.outcome = 'win' then 1 else 0 end"));
  assert.ok(schema.includes("case when new.score >= 100 then 1 else 0 end"));
  assert.ok(schema.includes('grant execute on function public.claim_scrabble_daily_challenge(date,text) to authenticated'));
  assert.ok(schema.includes('revoke all on function public.claim_scrabble_daily_challenge(date,text) from public, anon'));
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes("section==='tasks'"));
  assert.ok(cloud.includes("supabase.from('scrabble_daily_challenge_progress')"));
  assert.ok(cloud.includes("claimDailyChallenge"));
  assert.ok(cloud.includes("supabase.rpc('claim_scrabble_daily_challenge'"));
});

test('in-app notifications are private, event-driven, and readable through realtime',()=>{
  assert.ok(schema.includes('create table if not exists public.scrabble_notifications'));
  assert.ok(schema.includes('players read their own notifications'));
  assert.ok(schema.includes('players mark their own notifications read'));
  assert.match(schema,/function public\\.mark_scrabble_notification_read\\(notification_id uuid\\)[\\s\\S]*?security invoker/i);
  assert.ok(schema.includes('create trigger notify_scrabble_friend_request'));
  assert.ok(schema.includes('create trigger notify_scrabble_room_invite'));
  assert.ok(schema.includes('create trigger notify_scrabble_direct_message'));
  assert.ok(schema.includes('grant execute on function public.mark_scrabble_notification_read(uuid) to authenticated'));
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes("supabase.from('scrabble_notifications')"));
  assert.ok(cloud.includes("table:'scrabble_notifications'"));
  assert.ok(cloud.includes("supabase.rpc('mark_scrabble_notification_read'"));
  const dashboard=readFileSync(new URL('../src/Dashboard.jsx',import.meta.url),'utf8');
  assert.ok(dashboard.includes("'notifications'].includes(section)"));
  const app=readFileSync(new URL('../src/App.jsx',import.meta.url),'utf8');
  assert.ok(app.includes("id:'notifications'"));
});
