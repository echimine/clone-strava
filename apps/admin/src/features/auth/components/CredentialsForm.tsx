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
import { toast } from "sonner";
import { z } from "zod";
import type { TwoFactorMethod } from "../api";
import { useSignInWithPassword } from "../hooks/useSignInWithPassword";
import { authErrorMessage } from "../lib/auth-request-error";

const loginSchema = z.object({
  email: z.email("Adresse e-mail invalide"),
  password: z.string().min(1, "Mot de passe requis"),
});

type LoginValues = z.infer<typeof loginSchema>;

/** E-mail and password, the first step of the backoffice sign-in. */
export function CredentialsForm({
  onTwoFactorRequired,
}: {
  onTwoFactorRequired: (methods: TwoFactorMethod[]) => void;
}) {
  const signIn = useSignInWithPassword();
  const form = useForm<LoginValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: "", password: "" },
  });

  function onSubmit(values: LoginValues) {
    signIn.mutate(values, {
      onSuccess: (result) => {
        if (result.twoFactorRequired) {
          onTwoFactorRequired(result.methods);
        }
      },
      onError: (error) => toast.error(authErrorMessage(error)),
    });
  }

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
        <FormField
          control={form.control}
          name="email"
          render={({ field }) => (
            <FormItem>
              <FormLabel>E-mail</FormLabel>
              <FormControl>
                <Input type="email" autoComplete="username" {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
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
            </FormItem>
          )}
        />
        <Button
          type="submit"
          className="w-full"
          disabled={signIn.isPending || (signIn.isSuccess && !signIn.data.twoFactorRequired)}
        >
          Se connecter
        </Button>
      </form>
    </Form>
  );
}
