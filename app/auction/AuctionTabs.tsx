"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";

const TABS = [
  { href: "/auction", label: "Search" },
  { href: "/auction/deals", label: "Deals" },
  { href: "/auction/movers", label: "Movers" },
  { href: "/auction/best", label: "Best sellers" },
  { href: "/auction/crafting", label: "Crafting profits" },
  { href: "/auction/shopping", label: "Shopping list" },
  { href: "/auction/mine", label: "My auctions & gold" },
];

export default function AuctionTabs() {
  const path = usePathname();
  const house = useSearchParams().get("house");
  const q = house ? `?house=${house}` : "";
  return (
    <nav className="mb-4 flex flex-wrap gap-2" aria-label="Auction house sections">
      {TABS.map((t) => {
        const active = t.href === "/auction" ? path === "/auction" || path.startsWith("/auction/item") : path.startsWith(t.href);
        return (
          <Link key={t.href} href={t.href + q} aria-current={active ? "page" : undefined} className={`tab-btn ${active ? "tab-btn-active" : ""}`}>
            {t.label}
          </Link>
        );
      })}
    </nav>
  );
}
