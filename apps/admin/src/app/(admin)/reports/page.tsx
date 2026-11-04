import { ReportsView } from "@/features/reports/components/ReportsView";

export default function ReportsPage() {
  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Signalements</h1>
      <ReportsView />
    </div>
  );
}
