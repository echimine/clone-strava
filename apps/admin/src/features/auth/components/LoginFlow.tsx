"use client";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@repo/ui/components/card";
import { useState } from "react";
import type { TwoFactorMethod } from "../api";
import { CredentialsForm } from "./CredentialsForm";
import { SecondFactorForm } from "./SecondFactorForm";

/** Why the admin lands on the sign-in page, when it is not a plain visit. */
export type LoginNotice = "strong-session" | null;

/**
 * Backoffice sign-in (ADR-022 §5): password, then the second factor when
 * the account has 2FA. Both steps stay on `/login`: between them Better
 * Auth only holds a short-lived 2FA challenge cookie, no session.
 */
export function LoginFlow({ notice }: { notice: LoginNotice }) {
  const [methods, setMethods] = useState<TwoFactorMethod[] | null>(null);

  return (
    <div className="flex min-h-screen items-center justify-center p-6">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>{methods ? "Vérification en deux étapes" : "Connexion au backoffice"}</CardTitle>
          {methods ? (
            <CardDescription>Confirmez votre identité avec votre second facteur.</CardDescription>
          ) : null}
        </CardHeader>
        <CardContent className="space-y-4">
          {notice === "strong-session" && !methods ? (
            <p role="status" className="rounded-md bg-muted p-3 text-sm">
              Le backoffice demande une connexion par mot de passe et votre second facteur.
              Reconnectez-vous.
            </p>
          ) : null}
          {methods ? (
            <SecondFactorForm methods={methods} onRestart={() => setMethods(null)} />
          ) : (
            <CredentialsForm onTwoFactorRequired={setMethods} />
          )}
        </CardContent>
      </Card>
    </div>
  );
}
