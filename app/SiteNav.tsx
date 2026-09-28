"use client";

import { useEffect, useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../lib/supabase";

// Top bar (2026-09-28 layout rework) - used to also hold the row of nav
// buttons (Dashboard/Items/Friends/Leaderboards/Legacy/News); those moved
// to SiteSidebar.tsx (see app/navLinks.tsx for the shared list), so this is
// now just the slim strip across the top: a search box and the logged-in-
// as/login area, matching the reference screenshot's top bar.
//
// The search box reuses the real Items page rather than standing up new
// search logic - it navigates to /items?q=<query>. Whether ItemSearch.tsx
// actually reads that query param yet isn't something this file can see;
// worth confirming/wiring up as a follow-up once that file's in hand.
export default function SiteNav() {
  const router = useRouter();
  const [name, setName] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  const [query, setQuery] = useState("");

  useEffect(() => {
    async function loadName(userId: string | undefined) {
      if (!userId) {
        setName(null);
        setReady(true);
        return;
      }
      const { data } = await supabase
        .from("profiles")
        .select("display_name")
        .eq("id", userId)
        .single();
      setName(data?.display_name ?? "Unknown");
      setReady(true);
    }

    supabase.auth.getUser().then(({ data }) => loadName(data.user?.id));

    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      setTimeout(() => loadName(session?.user?.id), 0);
    });

    return () => listener.subscription.unsubscribe();
  }, []);

  async function handleLogout() {
    await supabase.auth.signOut();
  }

  function handleSearch(e: FormEvent) {
    e.preventDefault();
    const q = query.trim();
    router.push(q ? `/items?q=${encodeURIComponent(q)}` : "/items");
  }

  return (
    <nav className="nav-bar" style={{ marginBottom: 0 }}>
      {/* Room for the mobile sidebar toggle button (fixed top-left) so it
          never overlaps the search box on small screens. */}
      <div className="w-10 shrink-0 md:hidden" aria-hidden="true" />

      <form onSubmit={handleSearch} className="nav-search">
        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
          <circle cx="11" cy="11" r="7" />
          <path d="M21 21l-4.3-4.3" />
        </svg>
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search items..."
          className="nav-search-input"
        />
      </form>

      <div className="ml-auto flex min-h-9 items-center gap-3">
        {ready &&
          (name ? (
            <>
              <span className="text-sm text-gray-400">
                Logged in as <span className="font-bold text-white">{name}</span>
              </span>
              <button onClick={handleLogout} className="nav-btn">
                Log out
              </button>
            </>
          ) : (
            <Link href="/login" className="nav-btn nav-btn-active">
              Log in / Sign up
            </Link>
          ))}
      </div>
    </nav>
  );
}