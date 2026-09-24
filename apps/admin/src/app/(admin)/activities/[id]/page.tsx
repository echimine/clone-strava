import { ActivityDetailView } from "@/features/activities/components/ActivityDetailView";

export default async function ActivityDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Détail de l&apos;activité</h1>
      <ActivityDetailView id={id} />
    </div>
  );
}
