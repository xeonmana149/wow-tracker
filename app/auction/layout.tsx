import { Suspense } from "react";
import AuthStatus from "../AuthStatus";
import AuctionTabs from "./AuctionTabs";

export default function AuctionLayout({ children }: { children: React.ReactNode }) {
  return (
    <main className="mx-auto max-w-[1300px] p-4 md:p-6">
      <AuthStatus />
      <h1 className="text-2xl font-bold">Auction House</h1>
      <p className="mt-1 mb-4 max-w-3xl text-xs text-gray-500">
        Built from Blizzard&apos;s hourly snapshots of the auction house. Sales are worked out by
        watching listings disappear before they run out, so &quot;sold&quot; numbers are upper estimates
        (a cancelled auction looks the same as a sale).
      </p>
      <Suspense fallback={<div className="mb-4 h-9" />}>
        <AuctionTabs />
      </Suspense>
      {children}
    </main>
  );
}
