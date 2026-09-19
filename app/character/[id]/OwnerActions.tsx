"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { supabase } from "../../../lib/supabase";
import DeleteButton from "./DeleteButton";

export default function OwnerActions({
  characterId,
  ownerId,
}: {
  characterId: string;
  ownerId: string | null;
}) {
  const [isOwner, setIsOwner] = useState(false);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      setIsOwner(!!ownerId && data.user?.id === ownerId);
    });
  }, [ownerId]);

  if (!isOwner) return null;

  return (
    <div className="flex gap-3">
      <Link
        href={`/character/${characterId}/edit`}
        className="mt-8 rounded bg-blue-600 px-4 py-2 text-white"
      >
        Edit Character
      </Link>
      <DeleteButton id={characterId} />
    </div>
  );
}