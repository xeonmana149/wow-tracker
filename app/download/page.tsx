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
    </main>
  );
}