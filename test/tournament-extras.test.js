import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
test('tournaments support scheduling and virtual XP/coin prizes',()=>{
 for(const token of ['scheduled_at','prize_xp','prize_coins','spectators_enabled','prize_awarded_at','set_scrabble_tournament_details']) assert.ok(schema.includes(token),token);
 assert.ok(schema.includes('award_scrabble_tournament_prize'));
 assert.ok(schema.includes('scrabble_wallets.coins+excluded.coins'));
});
test('spectator RPC exposes only public board and score state, never private racks',()=>{
 const start=schema.lastIndexOf('create or replace function public.get_scrabble_tournament_spectator_state');
 const end=schema.indexOf('$function$;',start);
 assert.ok(start>=0&&end>start);
 const body=schema.slice(start,end);
 for(const token of ["'board'","'scores'","'turn_index'"]) assert.ok(body.includes(token));
 assert.ok(!body.includes('room_player_private'));
 assert.ok(!body.includes('room_tile_bag'));
 assert.ok(cloud.includes('get_scrabble_tournament_spectator_state'));
 assert.ok(cloud.includes('cloud-spectator-board'));
});
test('tournament details are owner-only while registration is open',()=>{
 const start=schema.lastIndexOf('create or replace function public.set_scrabble_tournament_details');
 const end=schema.indexOf('$function$;',start);
 const body=schema.slice(start,end);
 assert.ok(body.includes('owner_id=auth.uid()'));
 assert.ok(body.includes("status='registration'"));
});
