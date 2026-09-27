import CharacterLegacyPage from "../../../CharacterLegacyPage";

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <CharacterLegacyPage characterId={id} />;
}