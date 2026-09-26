import Link from "next/link";
import { DOWNLOAD_URLS } from "@/lib/versions";

export const dynamic = "force-static";

export default function DownloadPage() {
  return (
    <main className="mx-auto max-w-3xl p-4 md:p-6">
      <Link href="/" className="text-blue-400">← Back</Link>

      <h1 className="mt-4 text-3xl font-bold md:text-4xl">Downloads</h1>
      <p className="mt-2 text-gray-400">
        Two things to install, one time each. Both are safe to leave running - the
        addon does nothing until you're in-game, and the desktop app just sits quietly
        in your taskbar tray.
      </p>

      <section className="mt-6 rounded bg-neutral-800 p-5">
        <h2 className="text-xl font-bold">1. The addon (in-game)</h2>
        <p className="mt-2 text-sm text-gray-400">
          Collects your character&apos;s gear, stats and talents while you play.
        </p>
        <a
          href={DOWNLOAD_URLS.addon}
          download
          className="mt-4 inline-block rounded bg-blue-600 px-5 py-2.5 font-medium text-white hover:bg-blue-500"
        >
          Download addon (.zip)
        </a>
        <ol className="mt-4 list-decimal space-y-1 pl-5 text-sm text-gray-300">
          <li>Unzip it.</li>
          <li>
            Copy the <code>WoWForeverTracker</code> folder into your WoW{" "}
            <code>Interface/AddOns</code> folder.
          </li>
          <li>Restart WoW (or reload if it&apos;s already open).</li>
        </ol>
        <p className="mt-3 text-xs text-gray-500">
          Once the desktop app is installed and synced at least once, it&apos;ll also
          auto-update this addon for you - you shouldn&apos;t need to come back here
          again after this first install.
        </p>
      </section>

      <section className="mt-4 rounded bg-neutral-800 p-5">
        <h2 className="text-xl font-bold">2. The desktop app (Windows)</h2>
        <p className="mt-2 text-sm text-gray-400">
          Runs quietly in your system tray and syncs your characters to the website
          automatically - no copy-pasting, no terminal, and it keeps itself updated
          from here on.
        </p>

        <a
          href={DOWNLOAD_URLS.tray}
          className="mt-4 inline-block rounded bg-blue-600 px-5 py-2.5 font-medium text-white hover:bg-blue-500"
        >
          Download desktop app (.exe)
        </a>
        <ol className="mt-4 list-decimal space-y-1 pl-5 text-sm text-gray-300">
          <li>Run the installer and follow the setup wizard.</li>
          <li>
            The app opens its Settings window automatically the first time - paste in
            your account sync token (find it on your dashboard under &quot;Account
            Sync&quot;), tick the characters you want synced, and save.
          </li>
          <li>
            It&apos;ll then live in your system tray and sync automatically whenever
            you play - no need to open it again.
          </li>
        </ol>
        <p className="mt-3 text-xs text-gray-500">
          Windows may show a &quot;protected your PC&quot; warning since this isn&apos;t
          a signed app - click &quot;More info&quot; then &quot;Run anyway&quot;.
        </p>
      </section>
    </main>
  );
}