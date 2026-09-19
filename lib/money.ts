// WoW money is always tracked as one copper count: 100 copper = 1 silver,
// 10000 copper = 1 gold.
export function copperToParts(copper: number) {
  const c = Math.max(0, Math.round(copper || 0));
  return {
    gold: Math.floor(c / 10000),
    silver: Math.floor((c % 10000) / 100),
    copper: c % 100,
  };
}

export function partsToCopper(gold: number, silver: number, copper: number) {
  return (
    Math.max(0, Math.round(gold || 0)) * 10000 +
    Math.max(0, Math.round(silver || 0)) * 100 +
    Math.max(0, Math.round(copper || 0))
  );
}