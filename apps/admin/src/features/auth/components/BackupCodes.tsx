"use client";

import { Button } from "@repo/ui/components/button";
import { toast } from "sonner";

/**
 * Backup codes, shown once after 2FA setup (ADR-022 §5): the way back in
 * when the phone or the inbox is unavailable. Each code works once.
 */
export function BackupCodes({ codes, onDone }: { codes: string[]; onDone: () => void }) {
  const text = codes.join("\n");

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      toast.success("Codes copiés");
    } catch {
      toast.error("Copie impossible : notez les codes à la main.");
    }
  }

  function download() {
    const url = URL.createObjectURL(new Blob([`${text}\n`], { type: "text/plain" }));
    const link = document.createElement("a");
    link.href = url;
    link.download = "nervo-backoffice-codes-de-secours.txt";
    link.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">
        Conservez ces codes de secours en lieu sûr. Chacun permet une seule connexion si vous
        n&apos;avez plus accès à votre second facteur. Ils ne seront plus affichés.
      </p>
      <ul className="grid grid-cols-2 gap-2 rounded-md bg-muted p-3 font-mono text-sm">
        {codes.map((code) => (
          <li key={code}>{code}</li>
        ))}
      </ul>
      <div className="flex gap-2">
        <Button variant="outline" className="flex-1" onClick={copy}>
          Copier
        </Button>
        <Button variant="outline" className="flex-1" onClick={download}>
          Télécharger
        </Button>
      </div>
      <Button className="w-full" onClick={onDone}>
        Continuer vers le backoffice
      </Button>
    </div>
  );
}
