"use client";

import { Tabs, TabsContent, TabsList, TabsTrigger } from "@repo/ui/components/tabs";
import { FailuresTab } from "@/features/jobs/components/FailuresTab";
import { QueuesTab } from "@/features/jobs/components/QueuesTab";
import { useListUrlState } from "@/lib/list-url-state";

/**
 * The Jobs screen (ADR-038 §14): "Échecs", the business view it opens on, and "Files", the
 * technical view of the BullMQ queues. The tab is in the URL (`tab=files`), so the dashboard's
 * "Jobs en échec" tile can open "Files" directly.
 */
export function JobsView() {
  const list = useListUrlState();
  const tab = list.get("tab") === "files" ? "files" : "failures";

  return (
    <Tabs value={tab} onValueChange={(value) => list.setFilters({ tab: value === "files" ? "files" : undefined })}>
      <TabsList>
        <TabsTrigger value="failures">Échecs</TabsTrigger>
        <TabsTrigger value="files">Files</TabsTrigger>
      </TabsList>
      <TabsContent value="failures" className="pt-4">
        <FailuresTab />
      </TabsContent>
      <TabsContent value="files" className="pt-4">
        <QueuesTab list={list} />
      </TabsContent>
    </Tabs>
  );
}
