import { ActivitiesView } from "@/features/activities/components/ActivitiesView";

export default function ActivitiesPage() {
  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Activités</h1>
      <ActivitiesView />
    </div>
  );
}
