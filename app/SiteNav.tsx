"use client";

import { useEffect, useState, type ReactNode } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { supabase } from "../lib/supabase";

function Icon({ children }: { children: ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

const shield = (
  <Icon>
    <path d="M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6l7-3z" />
  </Icon>
);

const people = (
  <Icon>
    <circle cx="9" cy="8" r="3.5" />
    <path d="M2.5 20a6.5 6.5 0 0 1 13 0" />
    <circle cx="17.5" cy="9" r="2.5" />
    <path d="M17 14.5a5 5 0 0 1 4.5 5" />
  </Icon>
);

const trophy = (
  <Icon>
    <path d="M7 4h10v4a5 5 0 0 1-10 0V4z" />
    <path d="M7 6H4v1a3 3 0 0 0 3 3" />
    <path d="M17 6h3v1a3 3 0 0 1-3 3" />
    <path d="M12 13v4" />
    <path d="M8 20h8" />
  </Icon>
);

const news = (
  <Icon>
    <path d="M4 5h13a1 1 0 0 1 1 1v13H6a2 2 0 0 1-2-2V5z" />
    <path d="M18 9h2v8a2 2 0 0 1-2 2" />
    <path d="M8 9h6" />
    <path d="M8 13h6" />
  </Icon>
);

// A treasure chest for the Items search + Crafting Directory tab - loot
// chest reads as "items" more directly than the satchel/bag this replaces,
// and fits the game's own "open a chest, get loot" visual language.
const items = (
  <Icon>
    <path d="M4 10c0-3.9 3.6-7 8-7s8 3.1 8 7" />
    <rect x="4" y="10" width="16" height="9" rx="1.5" />
    <path d="M4 10h16" />
    <rect x="10.5" y="10" width="3" height="3.2" rx="0.6" />
  </Icon>
);

// A shield-and-star medal for the Legacy Challenges tab (2026-09-27) -
// distinct from the leaderboards trophy so the two don't read as the same
// destination at a glance.
const medal = (
  <Icon>
    <circle cx="12" cy="15" r="5" />
    <path d="M8 11L6 3h12l-2 8" />
    <path d="M12 12.5l1 2.2 2.4.2-1.8 1.6.6 2.3-2.2-1.3-2.2 1.3.6-2.3-1.8-1.6 2.4-.2z" />
  </Icon>
);

const links = [
  { href: "/", label: "Dashboard", icon: shield },
  { href: "/items", label: "Items", icon: items },
  { href: "/friends", label: "Friends", icon: people },
  { href: "/leaderboards", label: "Leaderboards", icon: trophy },
  // Account-wide, not tied to a character (2026-09-27) - see
  // app/AccountLegacyPage.tsx for why this isn't under /character/[id]/...
  { href: "/legacy", label: "Legacy", icon: medal },
  { href: "/news", label: "News", icon: news },
];

export default function SiteNav() {
  const pathname = usePathname();
  const [name, setName] = useState<string | null>(null);
  const [ready, setReady] = useState(false);

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

  const isActive = (href: string) =>
    href === "/" ? pathname === "/" : pathname.startsWith(href);

  return (
    <nav className="nav-bar" style={{ marginBottom: 0 }}>
      <Link href="/" className="nav-brand">
        WoW Forever Tracker
      </Link>

      {links.map((l) => (
        <Link
          key={l.href}
          href={l.href}
          className={`nav-btn ${isActive(l.href) ? "nav-btn-active" : ""}`}
        >
          {l.icon}
          {l.label}
        </Link>
      ))}

      {/* Empty until we know who's logged in, so nothing flickers */}
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