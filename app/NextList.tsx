import type { Todo } from "../lib/progress";

const DOT: Record<Todo["kind"], string> = {
  talent: "bg-purple-400",
  legacy: "bg-amber-400",
  profession: "bg-emerald-400",
  level: "bg-gray-400",
  setup: "bg-yellow-300",
  gear: "bg-red-400",
};

const BAR: Record<Todo["kind"], string> = {
  talent: "bg-purple-400",
  legacy: "bg-amber-400",
  profession: "bg-emerald-400",
  level: "bg-blue-400",
  setup: "bg-yellow-300",
  gear: "bg-red-400",
};

// A todo, optionally tagged with which character it belongs to - shown
// after the text in parentheses. Left as null/undefined for an
// account-wide todo (e.g. "No Enchanting on your account"), which isn't
// any one character's.
export type NextListItem = Todo & {
  character?: { id: string; name: string } | null;
};

export default function NextList({
  todos,
  limit,
  empty = "Nothing needs doing right now.",
}: {
  todos: NextListItem[];
  limit?: number;
  empty?: string;
}) {
  const shown = limit ? todos.slice(0, limit) : todos;
  const hidden = todos.length - shown.length;

  if (shown.length === 0) return <p className="text-sm text-gray-500">{empty}</p>;

  return (
    <ul className="flex flex-col gap-2.5 text-sm">
      {shown.map((t, i) => {
        // A bar only makes sense when there's a real target to measure
        // against - "Learn a profession" or the account-wide "missing
        // profession" todos have no value/max, so they stay a plain dotted
        // line same as before.
        const hasBar = typeof t.value === "number" && typeof t.max === "number" && t.max > 0;
        const percent = hasBar ? Math.min(100, Math.round((t.value! / t.max!) * 100)) : 0;
        const remaining = hasBar ? Math.max(0, t.max! - t.value!) : 0;

        return (
          <li key={i} className="flex items-start gap-2">
            <span className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${DOT[t.kind]}`} />
            <div className="min-w-0 flex-1">
              <div className="flex items-center justify-between gap-2">
                <span>
                  {t.text}
                  {t.character && <span className="text-gray-500"> ({t.character.name})</span>}
                </span>
                {hasBar && <span className="shrink-0 text-xs text-gray-500">{percent}%</span>}
              </div>
              {hasBar && (
                <>
                  <div className="mt-1 h-1.5 rounded bg-neutral-700">
                    <div className={`h-1.5 rounded ${BAR[t.kind]}`} style={{ width: `${percent}%` }} />
                  </div>
                  <div className="mt-0.5 text-xs text-gray-500">
                    {remaining.toLocaleString()} remaining
                  </div>
                </>
              )}
            </div>
          </li>
        );
      })}
      {hidden > 0 && <li className="pl-4 text-xs text-gray-500">+{hidden} more</li>}
    </ul>
  );
}