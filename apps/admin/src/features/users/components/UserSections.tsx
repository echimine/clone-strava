"use client";

import type { AdminUserDetail, AdminUserReport } from "@repo/contracts";
import { Badge } from "@repo/ui/components/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@repo/ui/components/card";
import { Skeleton } from "@repo/ui/components/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@repo/ui/components/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@repo/ui/components/tabs";
import Link from "next/link";
import type { ReactNode } from "react";
import { useUserReports, useUserSessions } from "@/features/users/hooks/useUsers";
import {
  caseStatusLabels,
  formatDateTime,
  levelLabels,
  methodLabels,
  reportReasonLabels,
  reportTargetLabels,
  sportLabel,
  visibilityLabels,
} from "@/features/users/lib/labels";

/** One numbered section of the user sheet, its title as a heading. */
export function SheetSection({ title, children }: { title: string; children: ReactNode }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>
          <h2>{title}</h2>
        </CardTitle>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex flex-col">
      <dt className="text-muted-foreground">{label}</dt>
      <dd>{children}</dd>
    </div>
  );
}

/** 2. Compte: sign-in methods, 2FA (Administrators), open sessions. */
export function AccountSection({ user }: { user: AdminUserDetail }) {
  const { data, isLoading } = useUserSessions(user.athlete.id);
  return (
    <SheetSection title="Compte">
      <dl className="mb-4 grid grid-cols-2 gap-4 text-sm md:grid-cols-4">
        <Field label="Méthodes de connexion">
          {user.account.signInMethods.map((method) => methodLabels[method]).join(", ")}
        </Field>
        {user.role === "admin" ? (
          <Field label="Double authentification">{user.account.twoFactorEnabled ? "Activée" : "Non configurée"}</Field>
        ) : null}
      </dl>
      <h3 className="mb-2 text-sm font-medium">Sessions ouvertes</h3>
      {isLoading ? (
        <Skeleton className="h-16 w-full" />
      ) : data && data.items.length > 0 ? (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Appareil</TableHead>
              <TableHead>Ouverte le</TableHead>
              <TableHead>Expire le</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.items.map((session) => (
              <TableRow key={session.id}>
                <TableCell title={session.userAgent ?? undefined}>{session.device ?? "Inconnu"}</TableCell>
                <TableCell>{formatDateTime(session.createdAt)}</TableCell>
                <TableCell>{formatDateTime(session.expiresAt)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : (
        <p className="text-sm text-muted-foreground">Aucune session ouverte.</p>
      )}
    </SheetSection>
  );
}

/** 3. Profil d'athlète: never birth date, gender nor weight (ADR-038 §5). */
export function ProfileSection({ user }: { user: AdminUserDetail }) {
  const { profile } = user;
  return (
    <SheetSection title="Profil d'athlète">
      <dl className="grid grid-cols-2 gap-4 text-sm md:grid-cols-4">
        <Field label="Ville">{profile.city ?? "—"}</Field>
        <Field label="Pays">{profile.country ?? "—"}</Field>
        <Field label="Sports pratiqués">
          {profile.sports.length > 0 ? profile.sports.map(sportLabel).join(", ") : "—"}
        </Field>
        <Field label="Level">{profile.level ? levelLabels[profile.level] : "—"}</Field>
        <Field label="Visibilité par défaut">{visibilityLabels[profile.defaultVisibility]}</Field>
      </dl>
      <h3 className="mb-1 mt-4 text-sm font-medium">Bio</h3>
      <p className="whitespace-pre-wrap text-sm">{profile.bio ?? "—"}</p>
    </SheetSection>
  );
}

/** 4. Activité: counts, last Activity, Streak, and the filtered Activities list. */
export function ActivitySection({ user }: { user: AdminUserDetail }) {
  return (
    <SheetSection title="Activité">
      <dl className="grid grid-cols-2 gap-4 text-sm md:grid-cols-4">
        <Field label="Activités">{user.activity.activityCount}</Field>
        <Field label="Dernière Activité">
          {user.activity.lastActivityAt ? formatDateTime(user.activity.lastActivityAt) : "—"}
        </Field>
        <Field label="Série">{`${user.activity.streakWeeks} semaine${user.activity.streakWeeks > 1 ? "s" : ""}`}</Field>
      </dl>
      <Link
        href={`/activities?userId=${user.athlete.id}`}
        className="mt-4 inline-block text-sm underline underline-offset-4"
      >
        Voir ses Activités
      </Link>
    </SheetSection>
  );
}

/** 5. Follows: counters and « Bloqué par N athlètes ». */
export function FollowsSection({ user }: { user: AdminUserDetail }) {
  const { followerCount, followingCount, blockedByCount } = user.follows;
  return (
    <SheetSection title="Follows">
      <dl className="grid grid-cols-2 gap-4 text-sm md:grid-cols-4">
        <Field label="Abonnés">{followerCount}</Field>
        <Field label="Abonnements">{followingCount}</Field>
        <Field label="Blocages">{`Bloqué par ${blockedByCount} athlète${blockedByCount > 1 ? "s" : ""}`}</Field>
      </dl>
    </SheetSection>
  );
}

function ReportTable({ reports, empty }: { reports: AdminUserReport[]; empty: string }) {
  if (reports.length === 0) {
    return <p className="text-sm text-muted-foreground">{empty}</p>;
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Motif</TableHead>
          <TableHead>Cible</TableHead>
          <TableHead>Date</TableHead>
          <TableHead>Statut</TableHead>
          <TableHead>Dossier</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {reports.map((report) => (
          <TableRow key={report.id}>
            <TableCell>{reportReasonLabels[report.reason]}</TableCell>
            <TableCell>{reportTargetLabels[report.targetType]}</TableCell>
            <TableCell>{formatDateTime(report.createdAt)}</TableCell>
            <TableCell>
              <Badge variant={report.status === "open" ? "destructive" : "secondary"}>
                {caseStatusLabels[report.status]}
              </Badge>
            </TableCell>
            <TableCell>
              <Link href={`/reports/${report.caseId}`} className="underline underline-offset-4">
                Ouvrir le dossier
              </Link>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

/** 7. Signalements: tabs « reçus » and « émis », each linking to its case (`/reports/<caseId>`). */
export function ReportsSection({ userId }: { userId: string }) {
  const { data, isLoading } = useUserReports(userId);
  return (
    <SheetSection title="Signalements">
      {isLoading || !data ? (
        <Skeleton className="h-16 w-full" />
      ) : (
        <Tabs defaultValue="received">
          <TabsList>
            <TabsTrigger value="received">{`Reçus (${data.received.length})`}</TabsTrigger>
            <TabsTrigger value="sent">{`Émis (${data.sent.length})`}</TabsTrigger>
          </TabsList>
          <TabsContent value="received">
            <ReportTable reports={data.received} empty="Aucun signalement reçu." />
          </TabsContent>
          <TabsContent value="sent">
            <ReportTable reports={data.sent} empty="Aucun signalement émis." />
          </TabsContent>
        </Tabs>
      )}
    </SheetSection>
  );
}
