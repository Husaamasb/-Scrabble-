import { isCloudConfigured, supabase } from './supabase.js';
import { createWiktionaryValidator } from '../game/wordValidator.js';

/**
 * Signed-in players use the server dictionary, which checks admin overrides,
 * then AI-first verdicts, then Wiktionary only if the AI provider is unavailable.
 * Offline guests retain the local Wiktionary fallback; this path is not AI-backed.
 */
export function createHybridDictionaryValidator(fetchImpl = globalThis.fetch) {
  const localValidator = createWiktionaryValidator(fetchImpl);
  return async ({ word, language }) => {
    const exactWord = typeof word === 'string' ? word.trim() : '';
    if (!exactWord || !['ar', 'en'].includes(language)) return false;

    if (isCloudConfigured && supabase) {
      try {
        const { data: sessionData } = await supabase.auth.getSession();
        if (sessionData?.session?.access_token) {
          const { data, error } = await supabase.functions.invoke('scrabble-dictionary', {
            body: { word: exactWord, language },
          });
          if (!error && typeof data?.valid === 'boolean') return data.valid;
        }
      } catch {
        // The local dictionary remains available if the cloud service is offline.
      }
    }
    return localValidator({ word: exactWord, language });
  };
}
