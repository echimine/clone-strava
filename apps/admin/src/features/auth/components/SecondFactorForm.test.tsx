import { fireEvent, screen, waitFor } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { hardNavigate } from "@/lib/navigation";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { SecondFactorForm } from "./SecondFactorForm";

vi.mock("@/lib/navigation", () => ({ hardNavigate: vi.fn() }));

const signedIn = { token: "t", user: { id: "u1", email: "admin@example.com" } };

function typeCode(label: RegExp, code: string) {
  fireEvent.change(screen.getByLabelText(label), { target: { value: code } });
  fireEvent.click(screen.getByRole("button", { name: "Vérifier" }));
}

/** ADR-022 §5: the second factor asked after the password, at sign-in. */
describe("SecondFactorForm", () => {
  beforeEach(() => {
    vi.mocked(hardNavigate).mockClear();
  });

  it("verifies the authenticator app code, without trusting the device, then opens the backoffice", async () => {
    let body: unknown;
    server.use(
      http.post("/api/auth/two-factor/verify-totp", async ({ request }) => {
        body = await request.json();
        return HttpResponse.json(signedIn);
      }),
    );
    renderWithProviders(<SecondFactorForm methods={["totp", "otp"]} onRestart={() => {}} />);

    typeCode(/code de l'application/i, "123456");

    await waitFor(() => expect(hardNavigate).toHaveBeenCalledWith("/"));
    // ADR-035 §3: a trusted device would skip the second factor next time.
    expect(body).toEqual({ code: "123456" });
  });

  it("sends a code by email, then verifies it", async () => {
    let sent = 0;
    let body: unknown;
    server.use(
      http.post("/api/auth/two-factor/send-otp", () => {
        sent += 1;
        return HttpResponse.json({ status: true });
      }),
      http.post("/api/auth/two-factor/verify-otp", async ({ request }) => {
        body = await request.json();
        return HttpResponse.json(signedIn);
      }),
    );
    // An admin who set 2FA up by email has no authenticator app.
    renderWithProviders(<SecondFactorForm methods={["otp"]} onRestart={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Envoyer le code" }));
    await screen.findByLabelText(/code reçu par e-mail/i);
    typeCode(/code reçu par e-mail/i, "654321");

    await waitFor(() => expect(hardNavigate).toHaveBeenCalledWith("/"));
    expect(sent).toBe(1);
    expect(body).toEqual({ code: "654321" });
  });

  it("accepts a backup code", async () => {
    let body: unknown;
    server.use(
      http.post("/api/auth/two-factor/verify-backup-code", async ({ request }) => {
        body = await request.json();
        return HttpResponse.json(signedIn);
      }),
    );
    renderWithProviders(<SecondFactorForm methods={["totp", "otp"]} onRestart={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Utiliser un code de secours" }));
    typeCode(/code de secours/i, "abcde-12345");

    await waitFor(() => expect(hardNavigate).toHaveBeenCalledWith("/"));
    expect(body).toEqual({ code: "abcde-12345" });
  });

  it("stays on the step and says so when the code is wrong", async () => {
    server.use(
      http.post("/api/auth/two-factor/verify-totp", () =>
        HttpResponse.json({ code: "INVALID_CODE", message: "Invalid code" }, { status: 401 }),
      ),
    );
    renderWithProviders(<SecondFactorForm methods={["totp", "otp"]} onRestart={() => {}} />);

    typeCode(/code de l'application/i, "000000");

    expect((await screen.findByRole("alert")).textContent).toBe("Code incorrect.");
    expect(hardNavigate).not.toHaveBeenCalled();
  });

  it("goes back to the password step once the sign-in challenge has expired", async () => {
    server.use(
      http.post("/api/auth/two-factor/verify-totp", () =>
        HttpResponse.json(
          { code: "INVALID_TWO_FACTOR_COOKIE", message: "Invalid two factor cookie" },
          { status: 401 },
        ),
      ),
    );
    const onRestart = vi.fn();
    renderWithProviders(<SecondFactorForm methods={["totp", "otp"]} onRestart={onRestart} />);

    typeCode(/code de l'application/i, "123456");

    await waitFor(() => expect(onRestart).toHaveBeenCalled());
  });
});
