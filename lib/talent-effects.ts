import { keyOf, type ClassData, type Ranks, type Talent } from "./talents";

export type Bonus = {
  add: Record<string, number>; // plain +N (or +N percentage points)
  pct: Record<string, number>; // +N% of the total
  estimated: Set<string>; // stats where some value was scaled from another rank
};

type Read = { stats: string[]; kind: "add" | "pct"; valueStr: string };
type Rule = { re: RegExp; read: (m: RegExpMatchArray) => Read | null };

const N = String.raw`(\d+(?:\.\d+)?)`;

// Each rule finds one kind of stat change in a sentence
const RULES: Rule[] = [
  {
    re: new RegExp(
      String.raw`increases? (?:your |the )?(?:total )?(strength|agility|intellect|stamina|spirit) by ${N}(%?)`,
      "gi"
    ),
    read: (m) => ({ stats: [m[1].toLowerCase()], kind: m[3] ? "pct" : "add", valueStr: m[2] }),
  },
  {
    re: new RegExp(
      String.raw`increases? (?:your )?(?:(?:total|maximum) )*(health|mana) by ${N}(%?)`,
      "gi"
    ),
    read: (m) => ({
      stats: [`max_${m[1].toLowerCase()}`],
      kind: m[3] ? "pct" : "add",
      valueStr: m[2],
    }),
  },
  {
    re: new RegExp(String.raw`armor(?: value| contribution)? from items by ${N}%`, "gi"),
    read: (m) => ({ stats: ["armor"], kind: "pct", valueStr: m[1] }),
  },
  {
    re: new RegExp(
      String.raw`(?:parry chance|chance to parry(?: enemy)?(?: melee)?(?: attacks)?) by ${N}%`,
      "gi"
    ),
    read: (m) => ({ stats: ["parry"], kind: "add", valueStr: m[1] }),
  },
  {
    re: new RegExp(
      String.raw`(?:dodge chance|chance to dodge(?: enemy)?(?: melee)?(?: attacks)?) by ${N}%`,
      "gi"
    ),
    read: (m) => ({ stats: ["dodge"], kind: "add", valueStr: m[1] }),
  },
  {
    // Melee crit only. "Holy Shock spell" and other spell-only crit is ignored.
    re: new RegExp(String.raw`critical strike(?: chance)? with ([^.%]*?) by ${N}%`, "gi"),
    read: (m) =>
      /melee|weapons|attacks/i.test(m[1])
        ? { stats: ["crit_strike"], kind: "add", valueStr: m[2] }
        : null,
  },
  {
    re: new RegExp(String.raw`chance to hit with ([^.%]*?) by ${N}%`, "gi"),
    read: (m) =>
      /melee|weapons|attacks/i.test(m[1])
        ? { stats: ["hit_equal", "hit_boss"], kind: "add", valueStr: m[2] }
        : null,
  },
  {
    re: new RegExp(
      String.raw`increases? (?:your )?(?:movement|run) speed(?: and mounted movement speed)? by ${N}%`,
      "gi"
    ),
    read: (m) => ({ stats: ["movement_speed"], kind: "add", valueStr: m[1] }),
  },
  {
    re: new RegExp(String.raw`increases? (?:your )?defense(?: skill)? by ${N}`, "gi"),
    read: (m) => ({ stats: ["defense"], kind: "add", valueStr: m[1] }),
  },
  {
    re: new RegExp(
      String.raw`increases? (?:your )?(?:melee |ranged )?attack power by ${N}(%?)`,
      "gi"
    ),
    read: (m) => ({ stats: ["attack_power"], kind: m[2] ? "pct" : "add", valueStr: m[1] }),
  },
  {
    re: new RegExp(
      String.raw`increases? (?:your )?(arcane|fire|frost|nature|shadow) resistance by ${N}`,
      "gi"
    ),
    read: (m) => ({ stats: [`res_${m[1].toLowerCase()}`], kind: "add", valueStr: m[2] }),
  },
];

// Sentences about procs and temporary effects aren't permanent stat changes
const CONDITIONAL =
  /\b(?:while|when|whenever|after|during|lasts)\b|for \d+(?:\.\d+)? (?:sec|min)|\d+% chance/i;

// Which number in the text (0, 1, 2...) sits at this position
function numberIndexAt(text: string, offset: number) {
  let i = 0;
  for (const n of text.matchAll(/\d+(?:\.\d+)?/g)) {
    const from = n.index ?? 0;
    if (offset >= from && offset < from + n[0].length) return i;
    i++;
  }
  return -1;
}

function parseText(text: string) {
  const found: (Read & { numIndex: number })[] = [];

  // Split into sentences, remembering where each one starts in the full text
  const sentences: { s: string; start: number }[] = [];
  let start = 0;
  for (const m of text.matchAll(/\.(?=\s|$)/g)) {
    const at = m.index ?? 0;
    sentences.push({ s: text.slice(start, at), start });
    start = at + 1;
  }
  sentences.push({ s: text.slice(start), start });

  for (const { s, start: sentenceStart } of sentences) {
    if (CONDITIONAL.test(s)) continue;
    for (const rule of RULES) {
      for (const m of s.matchAll(rule.re)) {
        const read = rule.read(m);
        if (!read) continue;
        const offset = sentenceStart + (m.index ?? 0) + m[0].lastIndexOf(read.valueStr);
        found.push({ ...read, numIndex: numberIndexAt(text, offset) });
      }
    }
  }
  return found;
}

// The stat changes a talent gives at a rank. Missing ranks are scaled from a lower one.
export function effectsAt(talent: Talent, rank: number) {
  if (rank <= 0 || !talent.passive) return [];

  const known = Object.keys(talent.desc)
    .map(Number)
    .sort((a, b) => a - b);
  if (known.length === 0) return [];

  const hasExact = !!talent.desc[String(rank)];
  const baseRank = hasExact ? rank : [...known].reverse().find((k) => k <= rank) ?? known[0];

  return parseText(talent.desc[String(baseRank)]).map((p) => {
    let value = parseFloat(p.valueStr);
    if (!hasExact && talent.scaleIdx.includes(p.numIndex)) {
      value = value * (rank / baseRank);
    }
    return { stats: p.stats, kind: p.kind, value, exact: hasExact };
  });
}

// Everything a whole build adds up to
export function buildBonus(data: ClassData, ranks: Ranks): Bonus {
  const bonus: Bonus = { add: {}, pct: {}, estimated: new Set() };

  for (const tree of data.trees) {
    for (const talent of tree.talents) {
      const rank = ranks[keyOf(tree, talent)] ?? 0;
      for (const effect of effectsAt(talent, rank)) {
        for (const stat of effect.stats) {
          const target = effect.kind === "add" ? bonus.add : bonus.pct;
          target[stat] = (target[stat] ?? 0) + effect.value;
          if (!effect.exact) bonus.estimated.add(stat);
        }
      }
    }
  }
  return bonus;
}

// Take stats that include the `from` build's talents and change them to match the `to` build
export function adjustStats(saved: Record<string, number>, from: Bonus, to: Bonus) {
  const out = { ...saved };
  const keys = new Set([
    ...Object.keys(from.add),
    ...Object.keys(from.pct),
    ...Object.keys(to.add),
    ...Object.keys(to.pct),
  ]);

  for (const k of keys) {
    const base = saved[k] ?? 0;
    const fromFactor = 1 + (from.pct[k] ?? 0) / 100;
    const toFactor = 1 + (to.pct[k] ?? 0) / 100;
    const value =
      (base * toFactor) / (fromFactor > 0 ? fromFactor : 1) +
      (to.add[k] ?? 0) -
      (from.add[k] ?? 0);
    out[k] = Math.round(value * 100) / 100;
  }
  return out;
}