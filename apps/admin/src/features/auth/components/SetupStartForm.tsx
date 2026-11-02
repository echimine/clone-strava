"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { Button } from "@repo/ui/components/button";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@repo/ui/components/form";
import { Input } from "@repo/ui/components/input";
import { useForm } from "react-hook-form";
import { z } from "zod";
import type { SetupMethod } from "../hooks/useTwoFactorSetup";

const startSchema = z.object({
  method: z.enum(["totp", "otp"]),
  password: z.string().min(1, "Mot de passe requis"),
});

type StartValues = z.infer<typeof startSchema>;

const METHODS: { value: SetupMethod; title: string; description: string }[] = [
  {
    value: "totp",
    title: "Application d'authentification",
    description: "Google Authenticator, 1Password, Authy… Fonctionne sans réseau.",
  },
  {
    value: "otp",
    title: "Code par e-mail",
    description: "Un code envoyé à chaque connexion, sans application à installer.",
  },
];

/** First step of the 2FA setup: the method, and the password to confirm it is the admin. */
export function SetupStartForm({
  error,
  pending,
  onSubmit,
}: {
  error: string | null;
  pending: boolean;
  onSubmit: (values: StartValues) => void;
}) {
  const form = useForm<StartValues>({
    resolver: zodResolver(startSchema),
    defaultValues: { method: "totp", password: "" },
  });

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
        <FormField
          control={form.control}
          name="method"
          render={({ field }) => (
            <fieldset className="space-y-2">
              <legend className="mb-2 text-sm font-medium">Second facteur</legend>
              {METHODS.map((method) => (
                <label
                  key={method.value}
                  className="flex cursor-pointer gap-3 rounded-md border p-3 has-checked:border-primary"
                >
                  <input
                    type="radio"
                    name={field.name}
                    value={method.value}
                    checked={field.value === method.value}
                    onChange={() => field.onChange(method.value)}
                    className="mt-1"
                  />
                  <span className="space-y-1">
                    <span className="block text-sm font-medium">{method.title}</span>
                    <span className="block text-xs text-muted-foreground">{method.description}</span>
                  </span>
                </label>
              ))}
            </fieldset>
          )}
        />
        <FormField
          control={form.control}
          name="password"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Mot de passe</FormLabel>
              <FormControl>
                <Input type="password" autoComplete="current-password" {...field} />
              </FormControl>
              <FormMessage />
              {error ? (
                <p role="alert" className="text-sm text-destructive">
                  {error}
                </p>
              ) : null}
            </FormItem>
          )}
        />
        <Button type="submit" className="w-full" disabled={pending}>
          Continuer
        </Button>
      </form>
    </Form>
  );
}
