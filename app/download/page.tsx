import Link from "next/link";
import { DOWNLOAD_URLS } from "@/lib/versions";

export const dynamic = "force-static";

export default function DownloadPage() {
  return (
    <main className="mx-auto max-w-3xl p-4 md:p-6">
      <Link href="/" className="text-blue-400">← Back</Link>

      <h1 className="mt-4 text-3xl font-bold md:text-4xl">Download</h1>
      <p className="mt-2 text-gray-400">
        One app, one install. It syncs your characters to the site automatically, sets
        up the in-game addon for you, and keeps both updated from then on - nothing
        else to download separately.
      </p>

      <section className="mt-6 rounded bg-neutral-800 p-5">
        <h2 className="text-xl font-bold">WoW Forever Tracker (Windows)</h2>
        <p className="mt-2 text-sm text-gray-400">
          Runs quietly in your system tray, installs the in-game addon for you, and
          syncs your characters automatically - no copy-pasting, no terminal.
        </p>

        <a
          href={DOWNLOAD_URLS.tray}
          className="mt-4 inline-block rounded bg-blue-600 px-5 py-2.5 font-medium text-white hover:bg-blue-500"
        >
          Download WoW Forever Tracker (.exe)
        </a>
        <ol className="mt-4 list-decimal space-y-1 pl-5 text-sm text-gray-300">
          <li>Run the installer and follow the setup wizard.</li>
          <li>
            The app opens its Settings window automatically the first time and asks
            you to pick your WoW <code>Interface/AddOns</code> folder - it installs
            the addon there for you.
          </li>
          <li>
            Paste in your account sync token (find it on your dashboard under
            &quot;Account Sync&quot;), tick the characters you want synced, and save.
          </li>
          <li>
            It&apos;ll then live in your system tray and keep everything - itself and
            the addon - updated automatically. No need to come back here again.
          </li>
        </ol>
        <p className="mt-3 text-xs text-gray-500">
          Windows may show a &quot;protected your PC&quot; warning since this isn&apos;t
          a signed app - click &quot;More info&quot; then &quot;Run anyway&quot;.
        </p>
      </section>

      <section className="mt-6 rounded bg-neutral-800 p-5">
        <h2 className="text-xl font-bold">Forever Gold (in-game addon)</h2>
        <p className="mt-2 text-sm text-gray-400">
          A gold-making addon: what to post, craft, farm and flip right now, with real
          auction sale rates, an auto-poster and a kills and loot tracker. Optional and
          separate from the tracker addon.
        </p>
        <p className="mt-3 text-sm text-gray-300">
          Have the app above? Open its Settings and press <b>Install Forever Gold</b> -
          it installs it and keeps it updated, and it&apos;s the only way to get the
          sale rates.
        </p>
        <a
          href={DOWNLOAD_URLS.foreverGold}
          className="mt-4 inline-block rounded bg-neutral-700 px-5 py-2.5 font-medium text-white hover:bg-neutral-600"
        >
          Download Forever Gold (.zip)
        </a>
        <ol className="mt-4 list-decimal space-y-1 pl-5 text-sm text-gray-300">
          <li>Close WoW.</li>
          <li>
            Unzip it into <code>World of Warcraft/_forever_/Interface/AddOns</code>, so
            you end up with <code>AddOns/ForeverGold/ForeverGold.toc</code>.
          </li>
          <li>Start the game and type <code>/gold</code>.</li>
        </ol>
      </section>

      <section className="mt-6 rounded bg-neutral-800 p-5">
        <h2 className="text-xl font-bold">Forever UI (optional interface addon)</h2>
        <p className="mt-2 text-sm text-gray-400">
          A dark-and-gold replacement for much of the game&apos;s interface: action bars,
          unit frames, minimap, bags, tooltips, a quest encyclopedia that can take quests
          in a row, and crafting costs in the profession window. Entirely optional.
        </p>
        <p className="mt-3 text-sm text-gray-300">
          Have the app above? Open its Settings and press <b>Install Forever UI</b> - it&apos;s
          only installed if you ask, and kept updated after that.
        </p>
        <a
          href={DOWNLOAD_URLS.foreverUI}
          className="mt-4 inline-block rounded bg-neutral-700 px-5 py-2.5 font-medium text-white hover:bg-neutral-600"
        >
          Download Forever UI (.zip)
        </a>
        <ol className="mt-4 list-decimal space-y-1 pl-5 text-sm text-gray-300">
          <li>Close WoW.</li>
          <li>
            Unzip it into <code>World of Warcraft/_forever_/Interface/AddOns</code>, so
            you end up with <code>AddOns/ForeverUI/ForeverUI.toc</code>.
          </li>
          <li>Start the game and type <code>/fui</code>.</li>
        </ol>
      </section>
    </main>
  );
}