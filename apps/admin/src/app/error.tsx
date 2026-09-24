"use client";

import { Button } from "@repo/ui/components/button";

export default function ErrorPage({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-6 text-center">
      <h1 className="text-lg font-semibold">Une erreur est survenue</h1>
      <p className="max-w-md text-sm text-muted-foreground">{error.message}</p>
      <Button onClick={reset}>Réessayer</Button>
    </div>
  );
}
