/**
 * Dictionary validation is deliberately injected: this module never guesses
 * whether a word exists. Connect a trusted Arabic/English AI dictionary service
 * and pass its validator function before allowing a move to be committed.
 */
export async function validateWords(words, language, validator) {
  if (typeof validator !== 'function') {
    return { valid:false, reason:'dictionary-service-not-configured' };
  }
  const results = await Promise.all(words.map(async word => {
    try { return Boolean(await validator({ word:word.letters, language })); }
    catch { return false; }
  }));
  return { valid:results.every(Boolean), words:words.map((w,i)=>({...w,accepted:results[i]})) };
}
