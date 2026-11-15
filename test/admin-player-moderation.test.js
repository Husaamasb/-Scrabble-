import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const admin=readFileSync(new URL('../supabase/functions/scrabble-admin/index.ts',import.meta.url),'utf8');
const panel=readFileSync(new URL('../src/AdminPanel.jsx',import.meta.url),'utf8');
test('admin player operations require secure app_metadata and protect admin accounts',()=>{
 assert.ok(admin.includes("actor.app_metadata?.scrabble_admin!==true"));
 assert.ok(admin.includes("targetData.user.app_metadata?.scrabble_admin===true"));
 assert.ok(admin.includes("ctx.supabaseAdmin.auth.admin.listUsers"));
 assert.ok(admin.includes("ctx.supabaseAdmin.auth.admin.updateUserById"));
 assert.ok(admin.includes('You cannot suspend your own account.'));
});
test('admin player UI uses server-side moderation actions',()=>{
 assert.ok(panel.includes("supabase.functions.invoke('scrabble-admin'"));
 assert.ok(panel.includes("moderatePlayer(p.id,'ban_user'"));
 assert.ok(panel.includes("moderatePlayer(p.id,'unban_user'"));
 assert.ok(panel.includes("'168h'"));
 assert.ok(panel.includes("'720h'"));
 assert.ok(panel.includes('banned_until'));
 assert.ok(panel.includes('is_admin'));
});
