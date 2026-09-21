import Link from "next/link";

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
          href="/downloads/WoWForeverTracker.zip"
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
      </section>

      <section className="mt-4 rounded bg-neutral-800 p-5">
        <h2 className="text-xl font-bold">2. The desktop app (Windows)</h2>
        <p className="mt-2 text-sm text-gray-400">
          Runs quietly in your system tray and syncs your characters to the website
          automatically - no copy-pasting, no terminal.
        </p>
        <div className="mt-3 rounded border border-amber-700/50 bg-amber-500/10 p-3 text-sm text-amber-200">
          <strong>Before you install:</strong> this needs{" "}
          <a
            href="https://nodejs.org/"
            target="_blank"
            rel="noopener noreferrer"
            className="underline hover:text-amber-100"
          >
            Node.js
          </a>{" "}
          installed first (one-time, free). Grab the &quot;LTS&quot; version, run its
          installer with the default options, then come back here.
        </div>

        <a
          href="/downloads/WowSyncApp.zip"
          download
          className="mt-4 inline-block rounded bg-blue-600 px-5 py-2.5 font-medium text-white hover:bg-blue-500"
        >
          Download desktop app (.zip)
        </a>
        <ol className="mt-4 list-decimal space-y-1 pl-5 text-sm text-gray-300">
          <li>Unzip it anywhere (e.g. your Desktop or Documents).</li>
          <li>
            Double-click <code>install.bat</code> and let it finish - it&apos;ll open
            a setup page in your browser and start the tray app automatically.
          </li>
          <li>
            Paste in your account sync token (find it on your dashboard under
            &quot;Account Sync&quot;), tick the characters you want synced, and save.
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
