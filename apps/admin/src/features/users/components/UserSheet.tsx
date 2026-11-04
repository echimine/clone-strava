"use client";

import type { AdminUserDetail } from "@repo/contracts";
import { Badge } from "@repo/ui/components/badge";
import { Card, CardContent } from "@repo/ui/components/card";
import { Skeleton } from "@repo/ui/components/skeleton";
import type { ReactNode } from "react";
import { UserActions } from "@/features/users/components/UserActions";
import { UserAvatar } from "@/features/users/components/UserIdentity";
import {
  AccountSection,
  ActivitySection,
  FollowsSection,
  ProfileSection,
  ReportsSection,
  SheetSection,
} from "@/features/users/components/UserSections";
import { useUserActions } from "@/features/users/hooks/useUserActions";
import { useUser } from "@/features/users/hooks/useUsers";
import { banLabel, formatDate } from "@/features/users/lib/labels";
import { ApiClientError } from "@/lib/apiClient";

export type UserSheetProps = {
  id: string;
  /**
   * Section 6 « Premium »: filled by the Premium feature (#215), composed by the page. Until
   * then the section says so.
   */
  premium?: ReactNode;
  /** Section 8 « Historique »: the Journal's `AuditHistory`, composed by the page. */
  history: ReactNode;
  /** More header actions composed by the page, after the account's own (#214's « Supprimer le compte »). */
  extraActions?: ReactNode;
};

/** 1. En-tête: Avatar, name, e-mail, Admin / Banni / Premium badges, sign-up, actions. */
function Header({ user, actions }: { user: AdminUserDetail; actions: ReactNode }) {
  return (
    <Card>
      <CardContent className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-4">
          <UserAvatar athlete={user.athlete} className="size-16" />
          <div className="flex flex-col gap-1">
            <h1 className="text-2xl font-semibold">{user.athlete.displayName || user.email}</h1>
            <p className="text-sm text-muted-foreground">{user.email}</p>
            <p className="text-sm text-muted-foreground">Inscrit le {formatDate(user.createdAt)}</p>
          </div>
          <div className="flex flex-wrap gap-2">
            {user.role === "admin" ? <Badge variant="secondary">Admin</Badge> : null}
            {user.ban ? <Badge variant="destructive">{banLabel(user.ban)}</Badge> : null}
            {user.premium.active ? <Badge>Premium</Badge> : null}
          </div>
        </div>
        {user.ban?.reason ? <p className="text-sm">Motif du Ban : {user.ban.reason}</p> : null}
        {actions}
      </CardContent>
    </Card>
  );
}

/**
 * The user sheet (ADR-038 §5) in eight sections: header with actions, account and sessions,
 * athlete profile, Activity, Follows, Premium (slot), Reports, Historique (slot). The page
 * composes the slots, since features do not import each other.
 */
export function UserSheet({ id, premium, history, extraActions }: UserSheetProps) {
  const { data: user, isLoading, error } = useUser(id);
  const actions = useUserActions(id);

  if (isLoading) {
    return <Skeleton className="h-64 w-full" />;
  }
  if (!user) {
    const notFound = error instanceof ApiClientError && error.status === 404;
    return (
      <p role="alert" className="text-sm text-destructive">
        {notFound ? "Utilisateur introuvable." : "Impossible de charger l'utilisateur."}
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <Header
        user={user}
        actions={
          <div className="flex flex-wrap gap-2">
            <UserActions user={user} actions={actions} />
            {extraActions}
          </div>
        }
      />
      <AccountSection user={user} />
      <ProfileSection user={user} />
      <ActivitySection user={user} />
      <FollowsSection user={user} />
      <SheetSection title="Premium">
        {premium ?? <p className="text-sm text-muted-foreground">Le détail Premium arrive bientôt.</p>}
      </SheetSection>
      <ReportsSection userId={id} />
      <SheetSection title="Historique">{history}</SheetSection>
    </div>
  );
}
