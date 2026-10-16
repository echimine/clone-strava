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

/** The backoffice carries the Nervo brand (ADR-032 §1). */
describe("backoffice branding", () => {
  it("titles the browser tab Nervo · Backoffice", () => {
    expect(metadata.title).toBe("Nervo · Backoffice");
    expect(metadata.description).toBe("Administration Nervo");
  });

  it("shows Nervo at the top of the sidebar", () => {
    render(
      <SidebarProvider>
        <AppSidebar me={{ id: "u1", name: "Ada", email: "ada@example.com" } as never} />
      </SidebarProvider>,
    );

    expect(screen.getByText("Nervo")).toBeTruthy();
    expect(screen.queryByText(/Like-Strava/)).toBeNull();
  });
});
