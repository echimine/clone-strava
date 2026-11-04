import { Suspense } from "react";
import { JournalView } from "@/features/audit/components/JournalView";

export default function JournalPage() {
  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Journal</h1>
      {/* The list reads its filters from the URL (`useSearchParams`). */}
      <Suspense>
        <JournalView />
      </Suspense>
    </div>
  );
}
