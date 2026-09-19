import { ROADMAP, type Milestone } from "../lib/roadmap";
import RoadmapImage from "./RoadmapImage";

const DAY = 86_400_000;

function startOf(m: Milestone) {
  const d = m.start ?? m.end;
  return d ? new Date(`${d}T00:00:00Z`).getTime() : null;
}

function endOf(m: Milestone) {
  const d = m.end ?? m.start;
  return d ? new Date(`${d}T23:59:59Z`).getTime() : null;
}

type State = "past" | "live" | "next" | "later" | "tbd";

export default function Roadmap() {
  const now = Date.now();

  // Work out which milestone is done, live, or coming up next
  const states = new Map<Milestone, State>();
  let nextFound = false;
  for (const season of ROADMAP) {
    for (const m of season.milestones) {
      const start = startOf(m);
      const end = endOf(m);
      if (start === null || end === null) {
        states.set(m, "tbd");
      } else if (end < now) {
        states.set(m, "past");
      } else if (start <= now) {
        states.set(m, "live");
      } else if (!nextFound) {
        states.set(m, "next");
        nextFound = true;
      } else {
        states.set(m, "later");
      }
    }
  }

  return (
    <section className="rounded bg-neutral-800 p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="text-xl font-bold">Roadmap 2026 | 2027</h2>
        <p className="text-xs text-gray-500">
          Blizzard&apos;s official roadmap. Content and timing are subject to change.
        </p>
      </div>

      <div className="mt-4 flex flex-col gap-4 xl:flex-row">
        <RoadmapImage />

        <div className="grid min-w-0 flex-1 content-start gap-3 sm:grid-cols-2">
          {ROADMAP.map((season) => (
            <div key={season.name} className="flex flex-col gap-2">
              <h3
                className="rounded border border-amber-900/70 py-1.5 text-center text-sm font-bold"
                style={{ background: "linear-gradient(180deg, #4a3b22, #241b0f)" }}
              >
                {season.name}
                {season.official && (
                  <span className="block text-[11px] font-normal text-amber-200/70">
                    {season.official}
                  </span>
                )}
              </h3>

              <ul className="flex flex-col gap-2">
                {season.milestones.map((m) => {
                  const state = states.get(m) ?? "later";
                  const start = startOf(m);
                  const daysAway =
                    start !== null ? Math.max(1, Math.ceil((start - now) / DAY)) : 0;

                  return (
                    <li
                      key={m.title}
                      className={`rounded p-3 ${state === "past" ? "opacity-60" : ""}`}
                      style={state === "next" ? { outlineColor: "#f2c65a" } : undefined}
                    >
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="font-bold text-amber-100">{m.title}</span>
                      </div>

                      <div className="mt-1 flex flex-wrap items-center gap-2 text-xs">
                        {m.date && <span className="chip">{m.date}</span>}
                        {state === "live" && <span className="chip chip-active">Now</span>}
                        {state === "next" && (
                          <span className="chip">
                            in {daysAway} {daysAway === 1 ? "day" : "days"}
                          </span>
                        )}
                        {state === "past" && <span className="text-gray-500">Done</span>}
                        {m.note && <span className="text-gray-400">{m.note}</span>}
                      </div>

                      {m.items && (
                        <ul className="mt-2 list-disc pl-5 text-sm text-gray-300">
                          {m.items.map((item) => (
                            <li key={item}>{item}</li>
                          ))}
                        </ul>
                      )}
                    </li>
                  );
                })}
              </ul>
            </div>
          ))}
        </div>
      </div>

      <p className="mt-3 text-xs text-gray-500">
        More news beyond this roadmap will be shared, and features will evolve based on player
        feedback.
      </p>
    </section>
  );
}