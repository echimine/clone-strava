"use client";

import { AppSidebar } from "@/components/AppSidebar";
import { useAdminAccess } from "@/features/auth/hooks/useAdminAccess";
import { useMe } from "@/features/me/hooks/useMe";
import { isLeavingForbiddenSession } from "@/lib/apiClient";
import { SidebarInset, SidebarProvider, SidebarTrigger } from "@repo/ui/components/sidebar";
import { Skeleton } from "@repo/ui/components/skeleton";
import { useRouter } from "next/navigation";
import { useEffect } from "react";

/**
 * ADR-013 §"Authentication and authorization" step 2: fetches the current
 * user through the API, redirects to `/login` on an invalid session, shows
 * "Accès refusé" for a non-administrator. For an administrator, it then
 * checks `/v1/admin` before showing any page: without 2FA the admin goes to
 * its setup, a session not opened by password + 2FA is closed (ADR-022 §5,
 * ADR-035 §3; both handled by `apiClient`). The API remains the sole
 * guarantor of authorization; this only improves the experience.
 */
export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const { data: me, isPending, isError, error } = useMe();
  const access = useAdminAccess(me?.role === "admin");

  useEffect(() => {
    if (isError && (error as { status?: number }).status === 401) {
      router.replace("/login");
    }
  }, [isError, error, router]);

  if (access.isError && !isLeavingForbiddenSession(access.error)) {
    // Shown by `app/error.tsx`, with its "Réessayer" button.
    throw access.error;
  }

  if (isPending || (me?.role === "admin" && !access.isSuccess)) {
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
