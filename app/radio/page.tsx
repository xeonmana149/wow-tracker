import type { Metadata } from "next";
import { Suspense } from "react";
import RadioHome from "./RadioHome";

export const metadata: Metadata = { title: "Azeroth Radio" };

export default function RadioPage() {
  return (
    <div className="mx-auto max-w-3xl space-y-4">
      <div>
        <h1 className="text-2xl font-bold text-amber-200">Azeroth Radio</h1>
        <p className="mt-1 text-sm text-gray-400">
          Stations that play around the clock. Tune in from the WoW Forever Tracker app and you&apos;ll hear the same song, at the same
          moment, as everyone else listening. Music plays through SoundCloud&apos;s own player.
        </p>
      </div>
      <Suspense fallback={<p className="text-sm text-gray-400">Loading stations...</p>}>
        <RadioHome />
      </Suspense>
    </div>
  );
}
