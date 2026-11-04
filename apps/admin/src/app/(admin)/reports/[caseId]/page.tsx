import { ReportCaseView } from "@/features/reports/components/ReportCaseView";

export default async function ReportCasePage({ params }: { params: Promise<{ caseId: string }> }) {
  const { caseId } = await params;

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Dossier de signalement</h1>
      <ReportCaseView caseId={caseId} />
    </div>
  );
}
