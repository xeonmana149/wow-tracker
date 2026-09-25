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

// A satchel/inventory bag for the Items search + Crafting Directory tab -
// reads as "items" at a glance the way WoW's own bag icon does, instead of
// the generic magnifying-glass-over-a-box it replaces.
const items = (
  <Icon>
    <path d="M8.5 8V6.5a3.5 3.5 0 0 1 7 0V8" />
    <path d="M5.5 8h13l-1.1 11.3a2 2 0 0 1-2 1.7H8.6a2 2 0 0 1-2-1.7L5.5 8z" />
    <path d="M9.5 11.5v2" />
    <path d="M14.5 11.5v2" />
  </Icon>
);

const links = [
  { href: "/", label: "Dashboard", icon: shield },
  { href: "/items", label: "Items", icon: items },
  { href: "/friends", label: "Friends", icon: people },
  { href: "/leaderboards", label: "Leaderboards", icon: trophy },
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