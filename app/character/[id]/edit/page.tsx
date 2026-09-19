import Link from "next/link";
import { notFound } from "next/navigation";
import { supabase } from "../../../../lib/supabase";
import EditForm from "./EditForm";

export const dynamic = "force-dynamic";

export default async function EditPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const { data: character } = await supabase
    .from("characters")
    .select("*")
    .eq("id", id)
    .single();

  if (!character) {
    notFound();
  }

  return (
    <main className="p-8">
      <Link href={`/character/${id}`} className="text-blue-400">← Back</Link>
      <h1 className="mt-4 text-3xl font-bold">Edit {character.name}</h1>
      <EditForm character={character} />
    </main>
  );
}