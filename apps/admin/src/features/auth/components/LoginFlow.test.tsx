import { fireEvent, screen, waitFor } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { hardNavigate } from "@/lib/navigation";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { LoginFlow } from "./LoginFlow";

vi.mock("@/lib/navigation", () => ({ hardNavigate: vi.fn() }));

function signInAs(email: string, password: string) {
  fireEvent.change(screen.getByLabelText("E-mail"), { target: { value: email } });
  fireEvent.change(screen.getByLabelText("Mot de passe"), { target: { value: password } });
  fireEvent.click(screen.getByRole("button", { name: "Se connecter" }));
}

/** Backoffice sign-in: password, then the second factor when 2FA is on (ADR-022 §5). */
describe("LoginFlow", () => {
  beforeEach(() => {
    vi.mocked(hardNavigate).mockClear();
  });

  it("asks for the second factor when the account has 2FA", async () => {
    server.use(
      http.post("/api/auth/sign-in/email", () =>
        HttpResponse.json({ twoFactorRedirect: true, twoFactorMethods: ["totp", "otp"] }),
      ),
    );
    renderWithProviders(<LoginFlow notice={null} />);

    signInAs("admin@example.com", "correct horse");

    expect(await screen.findByLabelText(/code de l'application/i)).toBeTruthy();
    expect(hardNavigate).not.toHaveBeenCalled();
  });

  it("opens the backoffice straight away for an account without 2FA (the admin pages then ask to set it up)", async () => {
    server.use(
      http.post("/api/auth/sign-in/email", () =>
        HttpResponse.json({ redirect: false, token: "t", user: { id: "u1" } }),
      ),
    );
    renderWithProviders(<LoginFlow notice={null} />);

    signInAs("admin@example.com", "correct horse");

    await waitFor(() => expect(hardNavigate).toHaveBeenCalledWith("/"));
  });

  it("explains why the admin was signed out after a weak session", () => {
    renderWithProviders(<LoginFlow notice="strong-session" />);

    expect(screen.getByRole("status").textContent).toMatch(
      /mot de passe et votre second facteur/,
    );
  });
});
