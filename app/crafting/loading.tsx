// Next.js shows this automatically the instant you click into /crafting,
// before the actual page has finished fetching from Supabase - without it,
// clicking the nav link just sits there blank/unresponsive-looking until
// the whole query comes back. A skeleton that roughly matches the real
// page's shape (title, search bar, profession tabs, a couple of loading
// rows) reads as "it's working" rather than "did that click do anything".
function Bar({ width }: { width: string }) {
  return <div className="h-8 animate-pulse rounded-lg bg-neutral-800" style={{ width }} />;
}

export default function CraftingLoading() {
  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <div className="h-9 w-64 animate-pulse rounded bg-neutral-800" />
      <div className="mt-3 h-4 w-96 max-w-full animate-pulse rounded bg-neutral-800/70" />

      <div className="mt-6 h-11 w-full animate-pulse rounded border border-neutral-700 bg-neutral-900" />

      <div className="mt-4 flex flex-wrap gap-2">
        <Bar width="7rem" />
        <Bar width="8rem" />
        <Bar width="6rem" />
        <Bar width="9rem" />
        <Bar width="7rem" />
      </div>

      <div className="mt-4 h-64 animate-pulse rounded bg-neutral-800" />
    </main>
  );
}