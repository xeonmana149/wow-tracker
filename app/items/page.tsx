import AuthStatus from "../AuthStatus";
import ItemSearch from "./ItemSearch";

export default function ItemsPage() {
  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <AuthStatus />

      <h1 className="text-3xl font-bold">Items</h1>
      <p className="mt-2 max-w-2xl text-sm text-gray-400">
        Browse the full classic item database. Anything a real character has actually been seen
        wearing or carrying shows its true, confirmed Forever data - everything else is
        Blizzard&apos;s original classic data, which Forever may have changed.
      </p>

      <div className="mt-5">
        <ItemSearch />
      </div>
    </main>
  );
}