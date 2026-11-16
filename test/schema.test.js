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



test('password login requires a verified email OTP before creating the main session',()=>{
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  const auth=readFileSync(new URL('../src/cloud/supabase.js',import.meta.url),'utf8');
  const passwordCheck=cloud.indexOf('await verifyPasswordWithoutPersisting(address,password)');
  const otpSend=cloud.indexOf("supabase.auth.signInWithOtp({email:address,options:{shouldCreateUser:false,emailRedirectTo:AUTH_REDIRECT_URL}})");
  assert.ok(passwordCheck>=0&&otpSend>passwordCheck);
  assert.ok(auth.includes('persistSession: false'));
  assert.ok(auth.includes("verifier.auth.signOut({ scope: 'local' })"));
  assert.ok(cloud.includes("setOtpType('email')"));
  assert.ok(cloud.includes('supabase.auth.verifyOtp({email,token:otp,type:otpType})'));
  assert.ok(!cloud.includes('supabase.auth.signInWithPassword'));
});

test('room creator selects the match end condition without adding turn timers',()=>{
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.match(schema,/end_condition text not null default 'classic' check\(end_condition in \('classic','bag_empty'\)\)/);
  assert.ok(schema.includes('create or replace function public.create_scrabble_room_with_rules'));
  assert.ok(schema.includes("if target.end_condition='bag_empty' then"));
  assert.ok(schema.includes("settle_scrabble_room(target_room,null,'bag_empty')"));
  assert.ok(schema.includes('revoke all on function public.create_scrabble_room_with_rules(text,boolean,int,text,text) from public,anon'));
  assert.ok(schema.includes('grant execute on function public.create_scrabble_room_with_rules(text,boolean,int,text,text) to authenticated'));
  assert.ok(cloud.includes("supabase.rpc('create_scrabble_room_with_rules'"));
  assert.ok(cloud.includes("value=\"bag_empty\""));
  assert.ok(cloud.includes("activeRoom.end_condition==='bag_empty'"));
  assert.ok(cloud.includes("matchEndMode:'طريقة انتهاء المباراة'"));
  assert.ok(!cloud.includes('turnTimer'));
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
  assert.ok(schema.includes('returns void language plpgsql security invoker set search_path = public'));
  assert.ok(schema.includes('create trigger notify_scrabble_friend_request'));
  assert.ok(schema.includes('create trigger notify_scrabble_room_invite'));
  assert.ok(schema.includes('create trigger notify_scrabble_direct_message'));
  assert.ok(schema.includes('create trigger notify_scrabble_turn_and_result'));
  assert.ok(schema.includes('create trigger notify_scrabble_daily_reward'));
  assert.ok(schema.includes('grant execute on function public.mark_scrabble_notification_read(uuid) to authenticated'));
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes("supabase.from('scrabble_notifications')"));
  assert.ok(cloud.includes("table:'scrabble_notifications'"));
  assert.ok(cloud.includes("supabase.rpc('mark_scrabble_notification_read'"));
  assert.ok(cloud.includes('turnNotice'));
  assert.ok(cloud.includes('resultNotice'));
  assert.ok(cloud.includes('rewardNotice'));
  const dashboard=readFileSync(new URL('../src/Dashboard.jsx',import.meta.url),'utf8');
  assert.ok(dashboard.includes("'notifications','store','tournaments','admin','report','settings'].includes(section)"));
  const app=readFileSync(new URL('../src/App.jsx',import.meta.url),'utf8');
  assert.ok(app.includes("id:'notifications'"));
});

test('virtual store purchases are server-authoritative and inventory is private',()=>{
  assert.ok(schema.includes('create table if not exists public.scrabble_store_catalog'));
  assert.ok(schema.includes('create table if not exists public.scrabble_wallets'));
  assert.ok(schema.includes('create table if not exists public.scrabble_inventory'));
  assert.ok(schema.includes('create or replace function public.purchase_scrabble_store_item(target_item text)'));
  assert.ok(schema.includes('grant execute on function public.purchase_scrabble_store_item(text) to authenticated'));
  assert.ok(schema.includes('if balance<item.price then raise exception'));
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes("supabase.from('scrabble_store_catalog')"));
  assert.ok(cloud.includes("supabase.rpc('purchase_scrabble_store_item'"));
  const dashboard=readFileSync(new URL('../src/Dashboard.jsx',import.meta.url),'utf8');
  assert.ok(dashboard.includes("'store','tournaments','admin','report','settings'].includes(section)"));
});

test('gifts transfer owned cosmetics only between friends and notify the recipient',()=>{
  assert.ok(schema.includes('create table if not exists public.scrabble_gifts'));
  assert.ok(schema.includes('create or replace function public.send_scrabble_gift(recipient uuid,target_item text)'));
  assert.ok(schema.includes('Gifts can only be sent to friends'));
  assert.ok(schema.includes('create or replace function public.resolve_scrabble_gift(target_gift uuid,accept_gift boolean)'));
  assert.ok(schema.includes('create trigger notify_scrabble_gift_received'));
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes("supabase.rpc('send_scrabble_gift'"));
  assert.ok(cloud.includes("supabase.rpc('resolve_scrabble_gift'"));
  assert.ok(cloud.includes('giftReceived'));
});

test("wooden chest displays the player's own rack without exposing the bot rack",()=>{
  const local=readFileSync(new URL('../src/LocalTable.jsx',import.meta.url),'utf8');
  assert.ok(local.includes('player.rack.map(tile=>'));
  assert.ok(local.includes('const humanTurn=!botMode||session.currentPlayer===0;'));
  assert.ok(local.includes('chestOpen&&humanTurn'));
  assert.ok(local.includes('placedIds.has(tile.id)'));
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes('Wooden letter chest'));
  assert.ok(cloud.includes('onlineChestOpen&&<div className="chest-row cloud-rack-tiles">'));
});

test('the main profile route displays the authenticated cloud profile rather than a local demo',()=>{
  const dashboard=readFileSync(new URL('../src/Dashboard.jsx',import.meta.url),'utf8');
  assert.ok(dashboard.includes("section==='profile'?'account':section"));
});

test('account settings persist privately for signed-in players',()=>{
  assert.ok(schema.includes('create table if not exists public.scrabble_user_settings'));
  assert.ok(schema.includes('players read own scrabble settings'));
  assert.ok(schema.includes('players create own scrabble settings'));
  assert.ok(schema.includes('players update own scrabble settings'));
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes("supabase.from('scrabble_user_settings').upsert"));
  assert.ok(cloud.includes('notification_preferences:preferences'));
  const dashboard=readFileSync(new URL('../src/Dashboard.jsx',import.meta.url),'utf8');
  assert.ok(dashboard.includes("'settings'].includes(section)"));
});

test('the original user-provided logo is used in the app header and retained as the app icon asset',()=>{
  const app=readFileSync(new URL('../src/App.jsx',import.meta.url),'utf8');
  assert.ok(app.includes("src={import.meta.env.BASE_URL+'logo-original.webp'}"));
  const fs=readFileSync(new URL('../public/icon.svg',import.meta.url),'utf8');
  assert.ok(fs.includes('data:image/webp;base64,'));
  const logo=readFileSync(new URL('../public/logo-original.webp',import.meta.url));
  assert.equal(logo.subarray(0,4).toString(),'RIFF');
});

test('room host can remove another player through a protected server RPC',()=>{
  assert.ok(schema.includes('create or replace function public.host_kick_scrabble_room_player(target_room uuid,target_player uuid)'));
  assert.ok(schema.includes('if r.host_id<>auth.uid() then raise exception'));
  assert.ok(schema.includes("if target_player=auth.uid() then raise exception 'Host cannot kick themselves'"));
  assert.ok(schema.includes("private.apply_scrabble_room_removal(target_room,target_player,'host_kick')"));
  assert.ok(schema.includes('grant execute on function public.host_kick_scrabble_room_player(uuid,uuid) to authenticated'));
});
test('room removal votes require active players, one ballot each, and a strict majority',()=>{
  assert.ok(schema.includes('create table if not exists public.scrabble_room_removal_votes'));
  assert.ok(schema.includes('create table if not exists public.scrabble_room_removal_ballots'));
  assert.ok(schema.includes('create unique index if not exists one_open_scrabble_removal_vote_per_room'));
  assert.ok(schema.includes('At least three active players are required to start a vote'));
  assert.ok(schema.includes('You have already voted'));
  assert.ok(schema.includes('yes_count>eligible_count/2'));
  assert.ok(schema.includes('no_count>eligible_count/2'));
  assert.ok(schema.includes('grant execute on function public.start_scrabble_room_removal_vote(uuid,uuid) to authenticated'));
  assert.ok(schema.includes('grant execute on function public.cast_scrabble_room_removal_vote(uuid,boolean) to authenticated'));
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes("supabase.rpc('host_kick_scrabble_room_player'"));
  assert.ok(cloud.includes("supabase.rpc('start_scrabble_room_removal_vote'"));
  assert.ok(cloud.includes("supabase.rpc('cast_scrabble_room_removal_vote'"));
  assert.ok(cloud.includes("table:'scrabble_room_removal_ballots'"));
  assert.ok(cloud.includes('voteYes'));
});


test('private rooms require an accepted invite and invite visibility is scoped to invitees',()=>{
  assert.match(schema,/if not target\.is_public and not exists \([\s\S]*?status = 'accepted'[\s\S]*?\) then[\s\S]*?An accepted room invitation is required/);
  assert.match(schema,/ri\.receiver_id = auth\.uid\(\)[\s\S]*?ri\.status in \('pending', 'accepted'\)/);
  assert.match(schema,/f\.user_low = auth\.uid\(\) and f\.user_high = receiver_id/);
  assert.match(schema,/revoke update on public\.room_invites from authenticated/);
  assert.match(schema,/grant update\(status\) on public\.room_invites to authenticated/);
  assert.match(schema,/one_pending_room_invite_per_recipient/);
});

test('room invitations update live for the intended recipient only',()=>{
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes("table:'room_invites'"));
  assert.ok(cloud.includes("filter:'receiver_id=eq.'+user.id"));
  assert.ok(cloud.includes('setIncomingInvites'));
});


test('room invites are included in Supabase realtime publication',()=>{
  assert.match(schema,/alter publication supabase_realtime add table public\.room_invites/);
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes("table:'room_invites'"));
  assert.ok(cloud.includes("filter:'receiver_id=eq.'+user.id"));
});


test('room host can start a rematch with the same active players and match rules',()=>{
  assert.ok(schema.includes('create or replace function public.rematch_scrabble_room(target_room uuid)'));
  assert.ok(schema.includes("previous.status <> 'finished'"));
  assert.ok(schema.includes("previous.host_id <> auth.uid()"));
  assert.ok(schema.includes('previous.max_players, previous.end_condition, previous.language'));
  assert.ok(schema.includes('not is_withdrawn'));
  assert.ok(schema.includes('insert into public.room_invites(room_id, sender_id, receiver_id)'));
  assert.ok(schema.includes('where room_id = created.id and user_id <> auth.uid()'));
  assert.ok(schema.includes('revoke all on function public.rematch_scrabble_room(uuid) from public, anon'));
  assert.ok(schema.includes('grant execute on function public.rematch_scrabble_room(uuid) to authenticated'));
  const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
  assert.ok(cloud.includes("supabase.rpc('rematch_scrabble_room'"));
  assert.ok(cloud.includes('onClick={rematchRoom}'));
  assert.ok(cloud.includes('activeRoom.host_id===user.id&&<button type="button" disabled={busy} onClick={rematchRoom}>'));
});
