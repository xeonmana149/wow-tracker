import { Suspense } from "react";
import ShoppingList from "./ShoppingList";

export default function ShoppingPage() {
  return (
    <Suspense fallback={<p className="text-sm text-gray-400">Loading your list...</p>}>
      <ShoppingList />
    </Suspense>
  );
}
