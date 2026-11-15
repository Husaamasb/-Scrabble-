import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const schema = readFileSync(new URL('../supabase/schema.sql', import.meta.url), 'utf8');
const migration = readFileSync(new URL('../supabase/migrations/20261115144936_harden_security_definer_search_paths.sql', import.meta.url), 'utf8');

const functions = [
  'accept_friend_request',
  'create_profile_for_new_user',
  'create_scrabble_room',
  'create_scrabble_room_with_rules',
  'emit_scrabble_notification',
  'exchange_scrabble_tiles',
  'finish_scrabble_room',
  'is_scrabble_room_member',
  'join_room_by_code',
  'notify_scrabble_daily_reward',
  'notify_scrabble_gift_received',
  'notify_scrabble_room_state',
  'pass_scrabble_turn',
  'purchase_scrabble_store_item',
  'rematch_scrabble_room',
  'resolve_scrabble_gift',
  'send_scrabble_gift',
  'set_scrabble_ready',
  'start_scrabble_room',
  'submit_scrabble_turn',
  'withdraw_scrabble_room',
];

test('all exposed security-definer functions pin an empty search_path', () => {
  for (const name of functions) {
    const header = new RegExp('create\\s+or\\s+replace\\s+function\\s+public\\.' + name + '\\s*\\(', 'i');
    const match = header.exec(schema);
    assert.ok(match, name + ' exists in schema');
    const bodyStart = schema.indexOf('$function$', match.index);
    assert.ok(bodyStart > match.index, name + ' has a function body');
    const definition = schema.slice(match.index, bodyStart);
    assert.match(definition, /set\\s+search_path\\s*=\\s*''/i, name + ' pins the empty search_path');
    assert.match(migration, new RegExp('alter\\s+function\\s+public\\.' + name + '\\s*\\(' , 'i'), name + ' is included in migration');
  }
  assert.equal((migration.match(/ALTER FUNCTION public\\./g) || []).length, functions.length);
});
