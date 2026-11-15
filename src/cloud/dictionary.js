import { isCloudConfigured, supabase } from './supabase.js';
import { createWiktionaryValidator } from '../game/wordValidator.js';

/**
 * Prefer the authenticated server dictionary (Wiktionary + optional AI review).
 * Keep local Wiktionary as a safe fallback for offline/local guests.
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
