import Link from "next/link";
import { Button } from "@repo/ui/components/button";

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-6 text-center">
      <h1 className="text-lg font-semibold">Page introuvable</h1>
      <p className="max-w-md text-sm text-muted-foreground">
        Cette page n&apos;existe pas ou a été déplacée.
      </p>
      <Button asChild>
        <Link href="/">Retour au tableau de bord</Link>
      </Button>
    </div>
  );
}
