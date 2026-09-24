"use client";

import type { MeResponse } from "@repo/contracts";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@repo/ui/components/sidebar";
import { Activity, LayoutDashboard, MapPinned, Users } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { signOut } from "@/lib/auth-client";

const navItems = [
  { href: "/", label: "Tableau de bord", icon: LayoutDashboard },
  { href: "/activities", label: "Activités", icon: Activity },
  { href: "/users", label: "Utilisateurs", icon: Users },
  { href: "/segments", label: "Segments", icon: MapPinned },
];

/** Backoffice navigation (ADR-013 §"Where to put a component"). */
export function AppSidebar({ me }: { me: MeResponse }) {
  const pathname = usePathname();

  return (
    <Sidebar>
      <SidebarHeader>
        <span className="px-2 text-sm font-semibold">Like-Strava</span>
      </SidebarHeader>
      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>
              {navItems.map((item) => (
                <SidebarMenuItem key={item.href}>
                  <SidebarMenuButton asChild isActive={pathname === item.href}>
                    <Link href={item.href}>
                      <item.icon />
                      <span>{item.label}</span>
                    </Link>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>
      <SidebarFooter>
        <div className="flex flex-col gap-1 px-2 py-1 text-xs text-muted-foreground">
          <span className="truncate font-medium text-foreground">{me.name}</span>
          <span className="truncate">{me.email}</span>
        </div>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              onClick={() =>
                signOut({
                  fetchOptions: {
                    // Full reload on purpose: drops the whole TanStack Query cache of the old session.
                    // eslint-disable-next-line @next/next/no-location-assign-relative-destination
                    onSuccess: () => window.location.assign("/login"),
                  },
                })
              }
            >
              Se déconnecter
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  );
}
