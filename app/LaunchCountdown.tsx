"use client";

import { useEffect, useState } from "react";
import { LAUNCH_TIME } from "../lib/roadmap";

const LAUNCH = new Date(LAUNCH_TIME).getTime();

const two = (n: number) => String(n).padStart(2, "0");

export default function LaunchCountdown() {
  // Empty until the page has loaded in the browser, so the server and browser agree
  const [now, setNow] = useState<number | null>(null);

  useEffect(() => {
    setNow(Date.now());
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  const left = now === null ? null : LAUNCH - now;

  if (left !== null && left <= 0) {
    return (
      <div className="launch-banner justify-center">
        <div className="launch-title text-center" style={{ fontSize: "1.3rem" }}>
          World of Warcraft: Forever is live!
        </div>
      </div>
    );
  }

  const total = left === null ? 0 : Math.floor(left / 1000);
  const units = [
    ["Days", Math.floor(total / 86400)],
    ["Hours", Math.floor((total % 86400) / 3600)],
    ["Minutes", Math.floor((total % 3600) / 60)],
    ["Seconds", total % 60],
  ] as const;

  const yourTime =
    now === null
      ? ""
      : new Date(LAUNCH).toLocaleString(undefined, {
          weekday: "short",
          day: "numeric",
          month: "short",
          hour: "numeric",
          minute: "2-digit",
        });

  return (
    <div className="launch-banner">
      <div className="launch-title">
        World of Warcraft: Forever
        <small>
          launches 4 Nov, 3:00 pm PST{yourTime && ` · your time: ${yourTime}`}
        </small>
      </div>

      <div className="launch-clock" role="timer" aria-label="Time until launch">
        {units.map(([label, value]) => (
          <div key={label} className="launch-unit">
            <div className="launch-num">{left === null ? "--" : two(value)}</div>
            <div className="launch-cap">{label}</div>
          </div>
        ))}
      </div>
    </div>
  );
}