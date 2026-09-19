import { loadSpecIcons } from "../../lib/server-data";
import CreateForm from "./CreateForm";

export const dynamic = "force-dynamic";

export default async function CreatePage() {
  const specIcons = await loadSpecIcons();
  return <CreateForm specIcons={specIcons} />;
}