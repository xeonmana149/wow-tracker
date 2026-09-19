export function GoldCoin({ size = 14 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 16 16"
      className="inline-block align-[-2px]"
      aria-hidden
    >
      <circle cx="8" cy="8" r="7" fill="#f0c040" stroke="#8a6a1a" strokeWidth="1" />
      <circle cx="8" cy="8" r="4" fill="none" stroke="#8a6a1a" strokeWidth="0.75" opacity="0.6" />
    </svg>
  );
}

export function SilverCoin({ size = 14 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 16 16"
      className="inline-block align-[-2px]"
      aria-hidden
    >
      <circle cx="8" cy="8" r="7" fill="#c7cdd6" stroke="#6b7280" strokeWidth="1" />
      <circle cx="8" cy="8" r="4" fill="none" stroke="#6b7280" strokeWidth="0.75" opacity="0.6" />
    </svg>
  );
}

export function CopperCoin({ size = 14 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 16 16"
      className="inline-block align-[-2px]"
      aria-hidden
    >
      <circle cx="8" cy="8" r="7" fill="#c9773f" stroke="#7a4420" strokeWidth="1" />
      <circle cx="8" cy="8" r="4" fill="none" stroke="#7a4420" strokeWidth="0.75" opacity="0.6" />
    </svg>
  );
}

// A plain gold amount (the site only stores whole gold, no silver/copper split)
import { copperToParts } from "../lib/money";

export function MoneyDisplay({ copper }: { copper: number }) {
  const { gold, silver, copper: c } = copperToParts(copper);
  return (
    <span className="inline-flex items-center gap-1.5">
      {gold > 0 && (
        <span className="inline-flex items-center gap-0.5">
          {gold.toLocaleString()} <GoldCoin />
        </span>
      )}
      {(gold > 0 || silver > 0) && (
        <span className="inline-flex items-center gap-0.5">
          {silver} <SilverCoin />
        </span>
      )}
      <span className="inline-flex items-center gap-0.5">
        {c} <CopperCoin />
      </span>
    </span>
  );
}

// Turns a tooltip line containing {gold}/{silver}/{copper} markers (from the
// addon) into text with real coin icons inline, e.g. "Sell Price: 3 {gold}
// 67 {copper}" -> "Sell Price: 3 <GoldCoin/> 67 <CopperCoin/>".
const COIN_TOKEN = /(\{gold\}|\{silver\}|\{copper\})/g;

export function renderMoneyLine(line: string) {
  return line.split(COIN_TOKEN).map((part, i) => {
    if (part === "{gold}") return <GoldCoin key={i} />;
    if (part === "{silver}") return <SilverCoin key={i} />;
    if (part === "{copper}") return <CopperCoin key={i} />;
    return part;
  });
}