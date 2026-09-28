import type { ReactNode } from "react";

// Shared between SiteNav (top bar) and SiteSidebar (2026-09-28 layout
// rework) - previously these icons/links lived only inside SiteNav.tsx;
// pulled out here so the sidebar can use the exact same icon set instead of
// a second, possibly-drifting copy.

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

const items = (
  <Icon>
    <path d="M4 10c0-3.9 3.6-7 8-7s8 3.1 8 7" />
    <rect x="4" y="10" width="16" height="9" rx="1.5" />
    <path d="M4 10h16" />
    <rect x="10.5" y="10" width="3" height="3.2" rx="0.6" />
  </Icon>
);

const medal = (
  <Icon>
    <circle cx="12" cy="15" r="5" />
    <path d="M8 11L6 3h12l-2 8" />
    <path d="M12 12.5l1 2.2 2.4.2-1.8 1.6.6 2.3-2.2-1.3-2.2 1.3.6-2.3-1.8-1.6 2.4-.2z" />
  </Icon>
);

// Real routes only (per Jordan's "don't invent functionality" rule on the
// layout rework) - this is the same 6 destinations the old horizontal
// SiteNav had, just now the sidebar's primary list instead of a top-bar
// row. Add to this one array and both the sidebar and (if it's ever needed
// again) the top bar pick it up.
export const NAV_LINKS = [
  { href: "/", label: "Dashboard", icon: shield },
  { href: "/items", label: "Items", icon: items },
  { href: "/friends", label: "Friends", icon: people },
  { href: "/leaderboards", label: "Leaderboards", icon: trophy },
  { href: "/legacy", label: "Legacy", icon: medal },
  { href: "/news", label: "News", icon: news },
];
