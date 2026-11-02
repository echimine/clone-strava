import { QueryClientProvider } from "@tanstack/react-query";
import { render, type RenderResult } from "@testing-library/react";
import type { ReactElement } from "react";
import { createQueryClient } from "@/lib/queryClient";

/** Renders with the app's TanStack Query client, fresh for each test. */
export function renderWithProviders(ui: ReactElement): RenderResult {
  return render(<QueryClientProvider client={createQueryClient()}>{ui}</QueryClientProvider>);
}
