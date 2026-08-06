import { createClient } from "@supabase/supabase-js";

function configuration() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!url || !publishableKey) {
    throw new Error("Supabase environment variables are not configured.");
  }

  return { url, publishableKey };
}

export function createSupabaseClient() {
  const { url, publishableKey } = configuration();
  return createClient(url, publishableKey);
}

export function getSupabaseConfiguration() {
  return configuration();
}
