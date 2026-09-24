"use client";

import { AppSidebar } from "@/components/AppSidebar";
import { useMe } from "@/features/me/hooks/useMe";
import { SidebarInset, SidebarProvider, SidebarTrigger } from "@repo/ui/components/sidebar";
import { Skeleton } from "@repo/ui/components/skeleton";
import { useRouter } from "next/navigation";
import { useEffect } from "react";

/**
 * ADR-013 §"Authentication and authorization" step 2: fetches the current
 * user through the API, redirects to `/login` on an invalid session, shows
 * "Accès refusé" for a non-administrator. The API remains the sole
 * guarantor of authorization; this only improves the experience.
 */
export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const { data: me, isPending, isError, error } = useMe();

  useEffect(() => {
    if (isError && (error as { status?: number }).status === 401) {
      router.replace("/login");
    }
  }, [isError, error, router]);

  if (isPending) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Skeleton className="h-8 w-48" />
      </div>
    );
  }

  if (isError) {
    return null;
  }

  if (me.role !== "admin") {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-2 text-center">
        <h1 className="text-lg font-semibold">Accès refusé</h1>
        <p className="max-w-md text-sm text-muted-foreground">
          Ce compte n&apos;a pas les droits d&apos;administration nécessaires.
        </p>
      </div>
    );
  }

  return (
    <SidebarProvider>
      <AppSidebar me={me} />
      <SidebarInset>
        <header className="flex h-14 items-center gap-2 border-b px-4">
          <SidebarTrigger />
        </header>
        <main className="flex-1 p-6">{children}</main>
      </SidebarInset>
    </SidebarProvider>
  );
}
