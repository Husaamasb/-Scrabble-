import { OFFLINE_WORDS } from './bot.js';

/**
 * Exact-entry dictionary lookup through Wiktionary's public MediaWiki API.
 * When the network is unavailable, use the bundled offline lexicon only.
 * It checks entries only; it never generates or guesses words.
 */
export function createWiktionaryValidator(fetchImpl = globalThis.fetch) {
  return async ({ word, language }) => {
    const lang = language === 'ar' ? 'ar' : language === 'en' ? 'en' : null;
    if (!lang || typeof word !== 'string' || !word.trim()) return false;
    const normalizedWord = word.normalize('NFC').trim();
    const offlineMatch = () => OFFLINE_WORDS[lang].has(lang === 'en' ? normalizedWord.toLowerCase() : normalizedWord);
    if (typeof fetchImpl !== 'function') return offlineMatch();
    const cacheKey = `scrabble:dictionary:${lang}:${word.trim()}`;
    try { if (globalThis.localStorage?.getItem(cacheKey) === 'valid') return true; } catch {}
    const endpoint = new URL(`https://${lang}.wiktionary.org/w/api.php`);
    endpoint.search = new URLSearchParams({
      action: 'query',
      format: 'json',
      formatversion: '2',
      titles: normalizedWord,
      origin: '*'
    }).toString();
    try {
      const response = await fetchImpl(endpoint.toString(), { headers: { Accept: 'application/json' } });
      if (!response.ok) throw new Error(`dictionary-http-${response.status}`);
      const data = await response.json();
      const page = data?.query?.pages?.[0];
      const valid = Boolean(page && !page.missing && !page.invalid);
      if (valid) { try { globalThis.localStorage?.setItem(cacheKey, 'valid'); } catch {} }
      return valid;
    } catch (error) {
      if (offlineMatch()) return true;
      throw error;
    }
  };
}

/**
 * All words created by a move must have exact dictionary entries.
 * A network failure is a rejection, never an automatic approval.
 */
export async function validateWords(words, language, validator) {
  if (typeof validator !== 'function') {
    return { valid:false, reason:'dictionary-service-not-configured' };
  }
  const results = await Promise.all(words.map(async word => {
    try { return Boolean(await validator({ word:word.letters, language })); }
    catch { return false; }
  }));
  return { valid:results.every(Boolean), words:words.map((w,i)=>({...w,accepted:results[i]})),
    reason:results.every(Boolean) ? undefined : 'word-not-accepted' };
}
