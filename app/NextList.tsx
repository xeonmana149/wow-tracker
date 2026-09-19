import type { Todo } from "../lib/progress";

const DOT: Record<Todo["kind"], string> = {
  talent: "bg-purple-400",
  legacy: "bg-amber-400",
  profession: "bg-emerald-400",
  level: "bg-gray-400",
  setup: "bg-yellow-300",
};

export default function NextList({
  todos,
  limit,
  empty = "Nothing needs doing right now.",
}: {
  todos: Todo[];
  limit?: number;
  empty?: string;
}) {
  const shown = limit ? todos.slice(0, limit) : todos;
  const hidden = todos.length - shown.length;

  if (shown.length === 0) return <p className="text-sm text-gray-500">{empty}</p>;

  return (
    <ul className="flex flex-col gap-1.5 text-sm">
      {shown.map((t, i) => (
        <li key={i} className="flex items-start gap-2">
          <span className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${DOT[t.kind]}`} />
          <span>{t.text}</span>
        </li>
      ))}
      {hidden > 0 && <li className="pl-4 text-xs text-gray-500">+{hidden} more</li>}
    </ul>
  );
}