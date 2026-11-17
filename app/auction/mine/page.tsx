import { Suspense } from "react";
import MyMarket from "./MyMarket";

export default function MyAuctionsPage() {
  return (
    <Suspense fallback={<p className="text-sm text-gray-400">Loading...</p>}>
      <MyMarket />
    </Suspense>
  );
}
