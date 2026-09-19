"use client";

import { useRouter } from "next/navigation";
import { supabase } from "../../../lib/supabase";

export default function DeleteButton({ id }: { id: string }) {
  const router = useRouter();

  async function handleDelete() {
    if (!confirm("Delete this character? This cannot be undone.")) return;

    const { error } = await supabase.from("characters").delete().eq("id", id);

    if (error) {
      alert(`Something went wrong: ${error.message}`);
    } else {
      router.push("/");
      router.refresh();
    }
  }

  return (
    <button
      onClick={handleDelete}
      className="mt-8 rounded bg-red-700 px-4 py-2 text-white"
    >
      Delete Character
    </button>
  );
}