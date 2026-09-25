import CharacterAchievementsPage from "../../../CharacterAchievementsPage";

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <CharacterAchievementsPage characterId={id} />;
}
