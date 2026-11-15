import { createClient } from '@supabase/supabase-js';

const env = import.meta.env || {};

// Supabase project URL and publishable key are public client configuration.
// RLS and database grants remain the authorization boundary.
const url = env.VITE_SUPABASE_URL?.trim() || 'https://rwcwuxraekgpaeujhxbg.supabase.co';
const anonKey = env.VITE_SUPABASE_ANON_KEY?.trim() || 'sb_publishable_r3-46V9HEuoTquTtFXKgeA_b0ZQlMi7';

export const isCloudConfigured = Boolean(url && anonKey);
export const supabase = isCloudConfigured
  ? createClient(url, anonKey, {
      auth: {
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: true,
        flowType: 'pkce',
      },
      realtime: { params: { eventsPerSecond: 10 } },
    })
  : null;

export async function verifyPasswordWithoutPersisting(email, password) {
  if (!isCloudConfigured) throw new Error('cloud-not-configured');
  const verifier = createClient(url, anonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });
  const { data, error } = await verifier.auth.signInWithPassword({ email, password });
  if (error) throw error;
  await verifier.auth.signOut({ scope: 'local' });
  return Boolean(data?.user?.id);
}
