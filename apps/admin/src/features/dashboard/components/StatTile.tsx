import Link from "next/link";
import type { ReactNode } from "react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@repo/ui/components/card";
import { cn } from "@repo/ui/lib/utils";

const numberFormat = new Intl.NumberFormat("fr-FR");

export function formatCount(value: number): string {
  return numberFormat.format(value);
}

/**
 * One dashboard figure (ADR-038 §15): its label, its number and an optional line below. With
 * `href`, the whole tile opens its screen.
 */
export function StatTile({
  label,
  value,
  footer,
  href,
}: {
  label: string;
  value: number;
  footer?: ReactNode;
  href?: string;
}) {
  const card = (
    <Card className={cn("h-full gap-2 py-4", href && "transition-colors hover:bg-accent/50")}>
      <CardHeader className="px-4">
        <CardDescription>{label}</CardDescription>
        <CardTitle className="text-2xl font-semibold tabular-nums">{formatCount(value)}</CardTitle>
      </CardHeader>
      {footer ? <CardContent className="px-4 text-xs text-muted-foreground">{footer}</CardContent> : null}
    </Card>
  );
  return href ? (
    <Link href={href} className="block rounded-xl">
      {card}
    </Link>
  ) : (
    card
  );
}
