"use client";

import { Button } from "@repo/ui/components/button";
import { useState } from "react";
import { toast } from "sonner";
import type { TwoFactorMethod } from "../api";
import {
  type SecondFactorKind,
  useSendEmailCode,
  useVerifySecondFactor,
} from "../hooks/useSecondFactor";
import { authErrorMessage, isExpiredSignIn } from "../lib/auth-request-error";
import { CodeForm } from "./CodeForm";

const LABELS: Record<SecondFactorKind, string> = {
  totp: "Code de l'application d'authentification",
  otp: "Code reçu par e-mail",
  backup: "Code de secours",
};

const SWITCH_LABELS: Record<SecondFactorKind, string> = {
  totp: "Utiliser l'application d'authentification",
  otp: "Recevoir un code par e-mail",
  backup: "Utiliser un code de secours",
};

/**
 * Second step of the sign-in (ADR-022 §5): the authenticator app code, a
 * code sent by email, or a backup code. `methods` comes from `signIn.email`
 * (`totp` only once an authenticator app is set up); backup codes always
 * work. No "trust this device" option (ADR-035 §3).
 */
export function SecondFactorForm({
  methods,
  onRestart,
}: {
  methods: TwoFactorMethod[];
  /** Back to the password step, when the 2FA challenge has expired. */
  onRestart: () => void;
}) {
  const kinds: SecondFactorKind[] = [...methods, "backup"];
  const [kind, setKind] = useState<SecondFactorKind>(kinds[0] ?? "backup");
  const verify = useVerifySecondFactor();
  const sendCode = useSendEmailCode();

  function choose(next: SecondFactorKind) {
    verify.reset();
    sendCode.reset();
    setKind(next);
  }

  function submit(code: string) {
    verify.mutate(
      { kind, code },
      {
        onError: (error) => {
          if (isExpiredSignIn(error)) {
            toast.error(authErrorMessage(error));
            onRestart();
          }
        },
      },
    );
  }

  const waitingForEmail = kind === "otp" && !sendCode.isSuccess;

  return (
    <div className="space-y-4">
      {kind === "otp" ? (
        <p className="text-sm text-muted-foreground">
          {sendCode.isSuccess
            ? "Un code vous a été envoyé par e-mail. Il est valable 5 minutes."
            : "Nous vous envoyons un code à l'adresse e-mail de votre compte."}
        </p>
      ) : null}

      {waitingForEmail ? (
        <div className="space-y-2">
          <Button
            className="w-full"
            disabled={sendCode.isPending}
            onClick={() => sendCode.mutate()}
          >
            Envoyer le code
          </Button>
          {sendCode.isError ? (
            <p role="alert" className="text-sm text-destructive">
              {authErrorMessage(sendCode.error)}
            </p>
          ) : null}
        </div>
      ) : (
        <CodeForm
          key={kind}
          label={LABELS[kind]}
          numeric={kind !== "backup"}
          error={verify.isError ? authErrorMessage(verify.error) : null}
          pending={verify.isPending || verify.isSuccess}
          onSubmit={submit}
        />
      )}

      <div className="flex flex-col items-start gap-1">
        {kind === "otp" && sendCode.isSuccess ? (
          <Button
            variant="link"
            className="h-auto px-0"
            disabled={sendCode.isPending}
            onClick={() => sendCode.mutate()}
          >
            Renvoyer le code
          </Button>
        ) : null}
        {kinds
          .filter((other) => other !== kind)
          .map((other) => (
            <Button
              key={other}
              variant="link"
              className="h-auto px-0"
              onClick={() => choose(other)}
            >
              {SWITCH_LABELS[other]}
            </Button>
          ))}
        <Button variant="link" className="h-auto px-0 text-muted-foreground" onClick={onRestart}>
          Changer de compte
        </Button>
      </div>
    </div>
  );
}
