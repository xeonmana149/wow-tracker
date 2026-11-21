// Checks that gold-trade "sales" (absurd prices) don't count as what an
// item sells for: npx tsx scripts/test-market-odd.mts
import { applySnapshot, computeRates, computeSite, H_SOLDP, type Listing } from "../lib/market";

let failed = 0;
function check(ok: boolean, what: string) {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) failed++;
}

const ITEM = 5140; // Flash Powder
const t0 = 1795000000;
const L = (id: number, qty: number, price: number, tl = 3): Listing => ({ id, item: ITEM, qty, price, tl });

// Hour 1: plenty at 30-40c, and one at 50g (gold changing hands)
const snap1 = [L(1, 200, 30), L(2, 200, 32), L(3, 200, 34), L(4, 200, 40), L(5, 1, 500000)];
// Hour 2: 100 of the 30c stack and the 50g one bought
const snap2 = [L(1, 100, 30), L(2, 200, 32), L(3, 200, 34), L(4, 200, 40)];
let state = applySnapshot(null, 113, t0, snap1);
state = applySnapshot(state, 113, t0 + 3600, snap2);
let rates = computeRates(state);
let r = rates.items[String(ITEM)];
check(r[2] === 30, `the 50g "sale" is left out: sells for ${r[2]}c (30c expected)`);

// Old days recorded before that rule: a few gold-trade sales among real ones
const day = Object.values(state.days)[0];
day.items[String(ITEM)][3] += 1; // one more sold...
day.items[String(ITEM)][4] += 500000; // ...for 50g
rates = computeRates(state);
r = rates.items[String(ITEM)];
const site = computeSite(state, rates);
const h = site.items[String(ITEM)].h;
check(r[2] > 0 && r[2] <= 40, `history from before falls back to the market price: ${r[2]}c`);
check(h[h.length - 1][H_SOLDP] <= 40, `and so is the day's chart value: ${h[h.length - 1][H_SOLDP]}c`);

if (failed) {
  console.log(`${failed} FAILED`);
  process.exit(1);
}
console.log("all ok");
