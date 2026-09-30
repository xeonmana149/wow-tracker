"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../lib/supabase";
import { iconUrlForFileId, wowIconUrl } from "../lib/icons";
import { avatarIconSrc, findAvatarIconOption } from "../lib/profileCustomization";

// Top bar (2026-09-28 layout rework) - used to also hold the row of nav
// buttons (Dashboard/Items/Friends/Leaderboards/Legacy/News); those moved
// to SiteSidebar.tsx (see app/navLinks.tsx for the shared list), so this is
// now just the slim strip across the top: a search box and the logged-in-
// as/login area, matching the reference screenshot's top bar.
//
// 2026-09-30: "the search function at the top should be items plus
// characters, plus accounts" - was previously just a shortcut into the
// Items page's own search. Now queries /api/search (items + characters +
// accounts in one call) and shows a live dropdown; pressing Enter without
// picking a result still falls back to the old "go search this on the
// Items page" behavior, so a plain item search still works exactly as
// before.

type ItemHit = { id: number; name: string; quality_color: string | null; icon: number | null; icon_name: string | null };
type CharacterHit = { id: string; name: string; level: number; class: string; race: string };
type AccountHit = { id: string; display_name: string | null; avatar_icon: string | null };

export default function SiteNav() {
  const router = useRouter();
  const [name, setName] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState<ItemHit[]>([]);
  const [characters, setCharacters] = useState<CharacterHit[]>([]);
  const [accounts, setAccounts] = useState<AccountHit[]>([]);
  const [searching, setSearching] = useState(false);
  const boxRef = useRef<HTMLDivElement | null>(null);
  const requestId = useRef(0);

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

  // Debounced combined search - fires 200ms after typing stops, and ignores
  // a stale response if a newer keystroke already kicked off another one.
  useEffect(() => {
    const trimmed = query.trim();
    if (trimmed.length < 2) {
      setItems([]);
      setCharacters([]);
      setAccounts([]);
      setSearching(false);
      return;
    }
    setSearching(true);
    const thisRequest = ++requestId.current;
    const handle = setTimeout(async () => {
      try {
        const res = await fetch(`/api/search?q=${encodeURIComponent(trimmed)}`);
        const data = await res.json();
        if (thisRequest !== requestId.current) return;
        setItems(data.items ?? []);
        setCharacters(data.characters ?? []);
        setAccounts(data.accounts ?? []);
      } catch {
        if (thisRequest === requestId.current) {
          setItems([]);
          setCharacters([]);
          setAccounts([]);
        }
      } finally {
        if (thisRequest === requestId.current) setSearching(false);
      }
    }, 200);
    return () => clearTimeout(handle);
  }, [query]);

  // Closes the dropdown on an outside click, same convention as any other
  // combobox-style menu on the site.
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (boxRef.current && !boxRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, []);

  async function handleLogout() {
    await supabase.auth.signOut();
  }

  function handleSearch(e: FormEvent) {
    e.preventDefault();
    const q = query.trim();
    setOpen(false);
    router.push(q ? `/items?q=${encodeURIComponent(q)}` : "/items");
  }

  function goTo(path: string) {
    setOpen(false);
    setQuery("");
    router.push(path);
  }

  const hasResults = items.length > 0 || characters.length > 0 || accounts.length > 0;
  const showDropdown = open && query.trim().length >= 2;

  return (
    <nav className="nav-bar" style={{ marginBottom: 0 }}>
      {/* Room for the mobile sidebar toggle button (fixed top-left) so it
          never overlaps the search box on small screens. */}
      <div className="w-10 shrink-0 md:hidden" aria-hidden="true" />

      <div ref={boxRef} className="relative">
        <form onSubmit={handleSearch} className="nav-search">
          <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <circle cx="11" cy="11" r="7" />
            <path d="M21 21l-4.3-4.3" />
          </svg>
          <input
            type="search"
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setOpen(true);
            }}
            onFocus={() => setOpen(true)}
            placeholder="Search items, characters, accounts..."
            className="nav-search-input"
          />
        </form>

        {showDropdown && (
          <div
            className="absolute left-0 top-full z-40 mt-1 w-[340px] max-w-[90vw] overflow-hidden rounded-md border border-neutral-700 bg-neutral-900 shadow-xl"
          >
            {searching && <p className="px-3 py-2 text-xs text-gray-500">Searching...</p>}
            {!searching && !hasResults && (
              <p className="px-3 py-2 text-xs text-gray-500">No matches for &ldquo;{query.trim()}&rdquo;.</p>
            )}

            {accounts.length > 0 && (
              <div className="border-b border-neutral-800 py-1">
                <p className="px-3 py-1 text-[10px] uppercase tracking-wide text-gray-500">Accounts</p>
                {accounts.map((a) => {
                  const avatarOption = findAvatarIconOption(a.avatar_icon);
                  const label = a.display_name ?? "Adventurer";
                  return (
                    <button
                      key={a.id}
                      type="button"
                      onClick={() => goTo(`/account/${a.id}`)}
                      className="flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm text-white hover:bg-neutral-800"
                    >
                      <span className="flex h-6 w-6 shrink-0 items-center justify-center overflow-hidden rounded-full border border-neutral-600 bg-neutral-800 text-[10px]">
                        {avatarOption ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img src={avatarIconSrc(avatarOption)} alt="" className="h-full w-full" />
                        ) : (
                          label.charAt(0).toUpperCase()
                        )}
                      </span>
                      {label}
                    </button>
                  );
                })}
              </div>
            )}

            {characters.length > 0 && (
              <div className="border-b border-neutral-800 py-1">
                <p className="px-3 py-1 text-[10px] uppercase tracking-wide text-gray-500">Characters</p>
                {characters.map((c) => (
                  <button
                    key={c.id}
                    type="button"
                    onClick={() => goTo(`/character/${c.id}`)}
                    className="flex w-full items-center justify-between gap-2 px-3 py-1.5 text-left text-sm text-white hover:bg-neutral-800"
                  >
                    <span>{c.name}</span>
                    <span className="text-xs text-gray-500">
                      Lv.{c.level} {c.race} {c.class}
                    </span>
                  </button>
                ))}
              </div>
            )}

            {items.length > 0 && (
              <div className="py-1">
                <p className="px-3 py-1 text-[10px] uppercase tracking-wide text-gray-500">Items</p>
                {items.map((it) => {
                  const iconSrc = iconUrlForFileId(it.icon) ?? (it.icon_name ? wowIconUrl(it.icon_name) : null);
                  const color = it.quality_color ? `#${it.quality_color}` : "#ffffff";
                  return (
                    <button
                      key={it.id}
                      type="button"
                      onClick={() => goTo(`/items?q=${encodeURIComponent(it.name)}`)}
                      className="flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm hover:bg-neutral-800"
                    >
                      <span className="h-5 w-5 shrink-0 overflow-hidden rounded border border-neutral-600 bg-neutral-800">
                        {iconSrc && (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img src={iconSrc} alt="" className="h-full w-full object-cover" />
                        )}
                      </span>
                      <span style={{ color }}>{it.name}</span>
                    </button>
                  );
                })}
                <button
                  type="button"
                  onClick={() => goTo(`/items?q=${encodeURIComponent(query.trim())}`)}
                  className="w-full px-3 py-1.5 text-left text-xs text-amber-400 hover:bg-neutral-800"
                >
                  See all item results →
                </button>
              </div>
            )}
          </div>
        )}
      </div>

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