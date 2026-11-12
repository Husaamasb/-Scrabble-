/**
 * Exact-entry dictionary lookup through Wiktionary's public MediaWiki API.
 * It checks entries only; it never generates or guesses words.
 */
export function createWiktionaryValidator(fetchImpl = globalThis.fetch) {
  return async ({ word, language }) => {
    if (typeof fetchImpl !== 'function') throw new Error('dictionary-fetch-unavailable');
    const lang = language === 'ar' ? 'ar' : language === 'en' ? 'en' : null;
    if (!lang || typeof word !== 'string' || !word.trim()) return false;
    const endpoint = new URL(`https://${lang}.wiktionary.org/w/api.php`);
    endpoint.search = new URLSearchParams({
      action: 'query',
      format: 'json',
      formatversion: '2',
      titles: word.trim(),
      origin: '*'
    }).toString();
    const response = await fetchImpl(endpoint.toString(), { headers: { Accept: 'application/json' } });
    if (!response.ok) throw new Error(`dictionary-http-${response.status}`);
    const data = await response.json();
    const page = data?.query?.pages?.[0];
    return Boolean(page && !page.missing && !page.invalid);
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
