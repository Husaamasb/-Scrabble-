import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
const admin=readFileSync(new URL('../src/AdminPanel.jsx',import.meta.url),'utf8');
test('admin access relies only on server-managed app_metadata and RLS',()=>{
 assert.ok(schema.includes("auth.jwt()->'app_metadata'->>'scrabble_admin'"));
 assert.ok(!schema.includes("auth.jwt()->'user_metadata'->>'scrabble_admin'"));
 assert.ok(schema.includes('admins review reports'));
 assert.ok(schema.includes('admins manage dictionary overrides'));
 assert.ok(admin.includes("user?.app_metadata?.scrabble_admin===true"));
});
test('admin room action can only close waiting rooms',()=>{
 const start=schema.lastIndexOf('create or replace function public.admin_close_scrabble_waiting_room');
 const end=schema.indexOf('$function$;',start);
 const body=schema.slice(start,end);
 assert.ok(body.includes('public.is_scrabble_admin()'));
 assert.ok(body.includes("status='waiting'"));
});
