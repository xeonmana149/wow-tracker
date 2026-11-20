import { handle, ok, rpc } from "../../../../lib/radio/server";

// Azeroth Radio: every station with what's on and how many are listening.
export async function GET() {
  return handle(async () => ok({ stations: await rpc("radio_list_stations", {}) }));
}
