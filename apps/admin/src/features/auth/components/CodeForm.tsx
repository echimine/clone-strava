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

const codeSchema = z.object({
  code: z.string().trim().min(1, "Code requis"),
});

type CodeValues = z.infer<typeof codeSchema>;

/**
 * One code field and its submit button, shared by the 2FA screens. The
 * refusal of the last submission (`error`) shows under the field.
 */
export function CodeForm({
  label,
  numeric,
  error,
  pending,
  onSubmit,
}: {
  label: string;
  /** A 6-digit TOTP or email code, as opposed to a backup code. */
  numeric: boolean;
  error: string | null;
  pending: boolean;
  onSubmit: (code: string) => void;
}) {
  const form = useForm<CodeValues>({
    resolver: zodResolver(codeSchema),
    defaultValues: { code: "" },
  });

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(({ code }) => onSubmit(code))} className="space-y-4">
        <FormField
          control={form.control}
          name="code"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{label}</FormLabel>
              <FormControl>
                <Input
                  autoComplete="one-time-code"
                  autoFocus
                  inputMode={numeric ? "numeric" : "text"}
                  maxLength={numeric ? 6 : 11}
                  placeholder={numeric ? "123456" : "abcde-12345"}
                  {...field}
                />
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
          Vérifier
        </Button>
      </form>
    </Form>
  );
}
