import { readFileSync } from "node:fs";
import path from "node:path";
import { SidebarProvider } from "@repo/ui/components/sidebar";
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { metadata } from "@/app/layout";
import { AppSidebar } from "./AppSidebar";

vi.mock("next/navigation", () => ({ usePathname: () => "/" }));

// jsdom has no matchMedia; the sidebar reads it to pick its mobile layout.
vi.stubGlobal("matchMedia", (query: string) => ({
  matches: false,
  media: query,
  addEventListener: () => {},
  removeEventListener: () => {},
}));

function renderSidebar() {
  return render(
    <SidebarProvider>
      <AppSidebar me={{ id: "u1", name: "Ada", email: "ada@example.com" } as never} />
    </SidebarProvider>,
  );
}

/** The backoffice carries the Nervo brand (ADR-032 §1). */
describe("backoffice branding", () => {
  it("titles the browser tab Nervo · Backoffice", () => {
    expect(metadata.title).toBe("Nervo · Backoffice");
    expect(metadata.description).toBe("Administration Nervo");
  });

  it("shows the NERVO · Backoffice lockup at the top of the sidebar", () => {
    renderSidebar();

    expect(screen.getByText("NERVO")).toBeTruthy();
    expect(screen.getByText("Backoffice")).toBeTruthy();
    expect(screen.queryByText(/Like-Strava/)).toBeNull();
  });

  it("draws the sidebar symbol with the master geometry (ADR-032 §2)", () => {
    const master = readFileSync(
      path.resolve(import.meta.dirname, "../../../../packages/ui/src/brand/nervo-symbol.svg"),
      "utf8",
    );
    const masterPath = /<path[^>]*\sd="([^"]+)"/.exec(master)?.[1];
    const { container } = renderSidebar();

    expect(masterPath).toBeDefined();
    expect(container.querySelector("[data-sidebar=header] svg path")?.getAttribute("d")).toBe(masterPath);
  });
});
