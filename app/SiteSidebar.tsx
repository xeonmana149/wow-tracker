"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { NAV_LINKS } from "./navLinks";

// Left sidebar (2026-09-28 layout rework, matching the reference screenshot
// Jordan sent) - the site's real navigation now lives here, vertically,
// instead of as a row of buttons across the top nav bar. SiteNav.tsx keeps
// the brand/search/login area in a slim top bar; this owns "which page am
// I on", same as the mockup's persistent left rail.
//
// Below md, this goes off-canvas (position: fixed, slid out to the left)
// and is opened with the toggle button rendered alongside it - the
// "collapse into a compact/mobile-friendly navigation" the layout doc asked
// for, without a heavier drawer library.
export default function SiteSidebar() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  const isActive = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="sidebar-toggle md:hidden"
        aria-label="Toggle navigation"
        aria-expanded={open}
      >
        <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
          <path d="M4 6h16M4 12h16M4 18h16" />
        </svg>
      </button>

      {open && <div className="sidebar-overlay md:hidden" onClick={() => setOpen(false)} aria-hidden="true" />}

      <aside className={`sidebar ${open ? "sidebar-open" : ""}`}>
        <Link href="/" className="sidebar-brand" onClick={() => setOpen(false)}>
          WoW Forever Tracker
        </Link>

        <nav className="sidebar-nav">
          {NAV_LINKS.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              onClick={() => setOpen(false)}
              className={`sidebar-link ${isActive(l.href) ? "sidebar-link-active" : ""}`}
            >
              {l.icon}
              <span>{l.label}</span>
            </Link>
          ))}
        </nav>
      </aside>
    </>
  );
}
