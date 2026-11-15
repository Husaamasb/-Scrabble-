import { isCloudConfigured, supabase } from './supabase.js';

const LOCAL_PREFIX = 'scrabble:local-session:';

function validSession(value) {
  return Boolean(value && value.version === 1 && value.session &&
    Array.isArray(value.session.players) && value.session.board);
}

export function collectLocalSessions(storage = globalThis.localStorage) {
  if (!storage) return [];
  const keys = Array.from({ length: storage.length }, (_, index) => storage.key(index))
    .filter(key => typeof key === 'string' && key.startsWith(LOCAL_PREFIX));
  const byGame = new Map();

  for (const localKey of keys) {
    const match = /^scrabble:local-session:(ar|en)(?::(bot|local))?$/.exec(localKey);
    if (!match) continue;
    let saved;
    try { saved = JSON.parse(storage.getItem(localKey) || 'null'); } catch { continue; }
    if (!validSession(saved)) continue;
    const language = match[1];
    const mode = match[2] || 'local';
    const gameKey = language + ':' + mode;
    const updatedAt = typeof saved.updatedAt === 'string' && Number.isFinite(Date.parse(saved.updatedAt))
      ? saved.updatedAt : new Date(0).toISOString();
    const entry = { user_id: null, game_key: gameKey, language, mode, session: saved.session,
      updated_at: updatedAt, local_key: localKey };
    const previous = byGame.get(gameKey);
    if (!previous || Date.parse(entry.updated_at) >= Date.parse(previous.updated_at) ||
      (entry.updated_at === previous.updated_at && localKey.endsWith(':' + mode))) {
      byGame.set(gameKey, entry);
    }
  }
  return [...byGame.values()];
}

export function mergeLocalAndCloudSessions(localRows, cloudRows) {
  const localByKey = new Map(localRows.map(row => [row.game_key, row]));
  const cloudByKey = new Map(cloudRows.map(row => [row.game_key, row]));
  const uploads = [];
  const downloads = [];

  for (const cloud of cloudRows) {
    const local = localByKey.get(cloud.game_key);
    if (!local || Date.parse(cloud.updated_at) > Date.parse(local.updated_at)) downloads.push(cloud);
    else uploads.push(local);
  }
  for (const local of localRows) {
    if (!cloudByKey.has(local.game_key)) uploads.push(local);
  }
  return { uploads, downloads };
}

export async function syncLocalSessionsToCloud(userId, {
  client = supabase,
  storage = globalThis.localStorage,
} = {}) {
  if (!userId || !isCloudConfigured || !client || !storage || globalThis.navigator?.onLine === false) {
    return { uploaded: 0, downloaded: 0 };
  }
  const localRows = collectLocalSessions(storage);
  const { data: cloudRows, error: readError } = await client
    .from('scrabble_saved_games')
    .select('game_key,language,mode,session,updated_at')
    .eq('user_id', userId);
  if (readError) throw readError;

  const { uploads, downloads } = mergeLocalAndCloudSessions(localRows, cloudRows || []);
  for (const row of downloads) {
    const localKey = LOCAL_PREFIX + row.language + ':' + row.mode;
    storage.setItem(localKey, JSON.stringify({
      version: 1, session: row.session, updatedAt: row.updated_at,
    }));
  }
  if (uploads.length) {
    const rows = uploads.map(({ local_key, ...row }) => ({ ...row, user_id: userId }));
    const { error } = await client.from('scrabble_saved_games')
      .upsert(rows, { onConflict: 'user_id,game_key' });
    if (error) throw error;
  }
  if (downloads.length) {
    globalThis.dispatchEvent?.(new Event('scrabble-saved-games-synced'));
  }
  return { uploaded: uploads.length, downloaded: downloads.length };
}

export async function saveLocalGameToCloud(userId, language, mode, session, updatedAt, client = supabase) {
  if (!userId || !isCloudConfigured || !client || globalThis.navigator?.onLine === false) return false;
  if (!['ar', 'en'].includes(language) || !['bot', 'local'].includes(mode) ||
    !session || !Array.isArray(session.players) || !session.board) return false;
  const { error } = await client.from('scrabble_saved_games').upsert({
    user_id: userId,
    game_key: language + ':' + mode,
    language,
    mode,
    session,
    updated_at: updatedAt || new Date().toISOString(),
  }, { onConflict: 'user_id,game_key' });
  if (error) throw error;
  return true;
}
