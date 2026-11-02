"use client";

import { Button } from "@repo/ui/components/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@repo/ui/components/card";
import { Skeleton } from "@repo/ui/components/skeleton";
import { QRCodeSVG } from "qrcode.react";
import { useEffect, useState } from "react";
import { hardNavigate } from "@/lib/navigation";
import type { TwoFactorEnrollment } from "../api";
import { useSendEmailCode } from "../hooks/useSecondFactor";
import { useSessionUser } from "../hooks/useSessionUser";
import {
  type SetupMethod,
  useConfirmTwoFactorSetup,
  useStartTwoFactorSetup,
} from "../hooks/useTwoFactorSetup";
import { authErrorMessage } from "../lib/auth-request-error";
import { totpSecretOf } from "../lib/totp-secret";
import { BackupCodes } from "./BackupCodes";
import { CodeForm } from "./CodeForm";
import { SetupStartForm } from "./SetupStartForm";

type Step =
  | { name: "start" }
  | { name: "verify"; method: SetupMethod; enrollment: TwoFactorEnrollment }
  | { name: "backup-codes"; codes: string[] };

/**
 * 2FA setup for an admin who has none yet (`ADMIN_2FA_REQUIRED`, ADR-022
 * §5): choose the authenticator app or email codes, prove it works with a
 * first code, then keep the backup codes.
 */
export function TwoFactorSetup() {
  const session = useSessionUser();
  const [step, setStep] = useState<Step>({ name: "start" });
  const start = useStartTwoFactorSetup();
  const confirm = useConfirmTwoFactorSetup();
  const sendCode = useSendEmailCode();

  // 2FA already on only matters before the setup starts: confirming it turns
  // 2FA on, and the backup codes must still show afterwards.
  const user = session.data;
  const leaveTo = session.isPending
    ? null
    : !user
      ? "/login"
      : user.twoFactorEnabled && step.name === "start"
        ? "/"
        : null;
  useEffect(() => {
    if (leaveTo) {
      hardNavigate(leaveTo);
    }
  }, [leaveTo]);

  function begin({ method, password }: { method: SetupMethod; password: string }) {
    start.mutate(password, {
      onSuccess: (enrollment) => {
        if (method === "otp") {
          sendCode.mutate();
        }
        setStep({ name: "verify", method, enrollment });
      },
    });
  }

  function verify(method: SetupMethod, enrollment: TwoFactorEnrollment, code: string) {
    confirm.mutate(
      { method, code },
      { onSuccess: () => setStep({ name: "backup-codes", codes: enrollment.backupCodes }) },
    );
  }

  if (!user || leaveTo) {
    return (
      <Shell title="Activer la vérification en deux étapes">
        <Skeleton className="h-32 w-full" />
      </Shell>
    );
  }

  if (step.name === "backup-codes") {
    return (
      <Shell title="Vérification en deux étapes activée">
        <BackupCodes codes={step.codes} onDone={() => hardNavigate("/")} />
      </Shell>
    );
  }

  if (step.name === "verify") {
    const { method, enrollment } = step;
    const confirmError = confirm.isError ? authErrorMessage(confirm.error) : null;
    return (
      <Shell title="Activer la vérification en deux étapes">
        {method === "totp" ? (
          <TotpEnrollment totpURI={enrollment.totpURI} />
        ) : (
          <p className="text-sm text-muted-foreground">
            {sendCode.isError
              ? authErrorMessage(sendCode.error)
              : `Un code a été envoyé à ${user.email}. Il est valable 5 minutes.`}
          </p>
        )}
        <CodeForm
          label={method === "totp" ? "Code de l'application d'authentification" : "Code reçu par e-mail"}
          numeric
          error={confirmError}
          pending={confirm.isPending}
          onSubmit={(code) => verify(method, enrollment, code)}
        />
        {method === "otp" ? (
          <Button
            variant="link"
            className="h-auto px-0"
            disabled={sendCode.isPending}
            onClick={() => sendCode.mutate()}
          >
            Renvoyer le code
          </Button>
        ) : null}
      </Shell>
    );
  }

  return (
    <Shell
      title="Activer la vérification en deux étapes"
      description={`Le backoffice exige un second facteur pour les administrateurs. Compte : ${user.email}`}
    >
      <SetupStartForm
        error={start.isError ? authErrorMessage(start.error) : null}
        pending={start.isPending}
        onSubmit={begin}
      />
    </Shell>
  );
}

function TotpEnrollment({ totpURI }: { totpURI: string }) {
  const secret = totpSecretOf(totpURI);
  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">
        Scannez ce QR code avec votre application d&apos;authentification, puis saisissez le code
        qu&apos;elle affiche.
      </p>
      <div className="flex justify-center rounded-md bg-white p-4">
        <QRCodeSVG value={totpURI} size={176} title="QR code de l'application d'authentification" />
      </div>
      {secret ? (
        <p className="text-xs text-muted-foreground">
          Ou saisissez cette clé à la main :{" "}
          <code className="font-mono text-sm break-all text-foreground">{secret}</code>
        </p>
      ) : null}
    </div>
  );
}

function Shell({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen items-center justify-center p-6">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>{title}</CardTitle>
          {description ? <CardDescription>{description}</CardDescription> : null}
        </CardHeader>
        <CardContent className="space-y-4">{children}</CardContent>
      </Card>
    </div>
  );
}
