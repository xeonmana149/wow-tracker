import { loadCardData } from "../lib/server-data";
import Dashboard from "./Dashboard";

export const dynamic = "force-dynamic";

export default async function Home() {
  const { specIcons, treeNames } = await loadCardData();
  return <Dashboard specIcons={specIcons} treeNames={treeNames} />;
}