import { JobsView } from "@/features/jobs/components/JobsView";

export default function JobsPage() {
  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Jobs</h1>
      <JobsView />
    </div>
  );
}
