import AuthStatus from "../AuthStatus";
import ItemSearch from "./ItemSearch";

export default function ItemsPage() {
  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <AuthStatus />

      <h1 className="text-2xl font-bold">Items</h1>
      <p className="mt-1 max-w-2xl text-xs text-gray-500">
        Browse World of Warcraft: Forever&apos;s item database.
      </p>

      <div className="mt-2">
        <ItemSearch />
      </div>
    </main>
  );
}