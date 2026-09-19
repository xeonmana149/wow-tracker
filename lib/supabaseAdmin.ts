import { createClient } from "@supabase/supabase-js";

// Server-only. Uses the Supabase service role key, which bypasses Row
// Level Security entirely - this must NEVER be imported from a "use
// client" component, and the key must never be prefixed with NEXT_PUBLIC_
// (that prefix ships a variable to the browser). This client exists only
// so the auto-sync API route can write to a character's data on behalf of
// a companion app that has no logged-in browser session to prove it's the
// owner - the sync_token is what proves that instead.
export const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);