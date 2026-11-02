import { fireEvent, screen, waitFor } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { hardNavigate } from "@/lib/navigation";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { TwoFactorSetup } from "./TwoFactorSetup";

vi.mock("@/lib/navigation", () => ({ hardNavigate: vi.fn() }));

const SECRET = "JBSWY3DPEHPK3PXP";
const BACKUP_CODES = ["aaaaa-11111", "bbbbb-22222", "ccccc-33333"];

function sessionOf(twoFactorEnabled: boolean) {
  return http.get("/api/auth/get-session", () =>
    HttpResponse.json({
      session: { id: "s1", userId: "u1", token: "t", expiresAt: "2099-01-01T00:00:00.000Z" },
      user: { id: "u1", email: "admin@example.com", name: "Admin", twoFactorEnabled },
    }),
  );
}

function enableWith(bodies: unknown[]) {
  return http.post("/api/auth/two-factor/enable", async ({ request }) => {
    const body = (await request.json()) as { password: string };
    bodies.push(body);
    if (body.password !== "correct horse") {
      return HttpResponse.json({ code: "INVALID_PASSWORD", message: "Invalid password" }, { status: 400 });
    }
    return HttpResponse.json({
      totpURI: `otpauth://totp/Nervo:admin%40example.com?secret=${SECRET}&issuer=Nervo&digits=6&period=30`,
      backupCodes: BACKUP_CODES,
    });
  });
}

function startWith(password: string) {
  fireEvent.change(screen.getByLabelText("Mot de passe"), { target: { value: password } });
  fireEvent.click(screen.getByRole("button", { name: "Continuer" }));
}

function typeCode(label: RegExp, code: string) {
  fireEvent.change(screen.getByLabelText(label), { target: { value: code } });
  fireEvent.click(screen.getByRole("button", { name: "Vérifier" }));
}

/** ADR-022 §5: an admin without 2FA sets it up, by authenticator app or by email. */
describe("TwoFactorSetup", () => {
  beforeEach(() => {
    vi.mocked(hardNavigate).mockClear();
  });

  it("sets up an authenticator app, then shows the backup codes before opening the backoffice", async () => {
    const enableBodies: unknown[] = [];
    let verifyBody: unknown;
    server.use(
      sessionOf(false),
      enableWith(enableBodies),
      http.post("/api/auth/two-factor/verify-totp", async ({ request }) => {
        verifyBody = await request.json();
        return HttpResponse.json({ token: "t2", user: { id: "u1" } });
      }),
    );
    renderWithProviders(<TwoFactorSetup />);

    await screen.findByText(/admin@example.com/);
    startWith("correct horse");

    // The key to type by hand when the QR code cannot be scanned.
    expect(await screen.findByText(SECRET)).toBeTruthy();
    typeCode(/code de l'application/i, "123456");

    for (const code of BACKUP_CODES) {
      expect(await screen.findByText(code)).toBeTruthy();
    }
    expect(enableBodies).toEqual([{ password: "correct horse" }]);
    expect(verifyBody).toEqual({ code: "123456" });
    expect(hardNavigate).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "Continuer vers le backoffice" }));
    expect(hardNavigate).toHaveBeenCalledWith("/");
  });

  it("sets up codes by email: sends a first code and turns 2FA on once it is verified", async () => {
    let sent = 0;
    let verifyBody: unknown;
    server.use(
      sessionOf(false),
      enableWith([]),
      http.post("/api/auth/two-factor/send-otp", () => {
        sent += 1;
        return HttpResponse.json({ status: true });
      }),
      http.post("/api/auth/two-factor/verify-otp", async ({ request }) => {
        verifyBody = await request.json();
        return HttpResponse.json({ token: "t2", user: { id: "u1" } });
      }),
    );
    renderWithProviders(<TwoFactorSetup />);

    await screen.findByText(/admin@example.com/);
    fireEvent.click(screen.getByRole("radio", { name: /code par e-mail/i }));
    startWith("correct horse");

    typeCode(/code reçu par e-mail/i, await waitForSentCode(() => sent));

    expect(await screen.findByText(BACKUP_CODES[0]!)).toBeTruthy();
    expect(verifyBody).toEqual({ code: "424242" });
  });

  it("asks for the password again when it is wrong", async () => {
    server.use(sessionOf(false), enableWith([]));
    renderWithProviders(<TwoFactorSetup />);

    await screen.findByText(/admin@example.com/);
    startWith("wrong");

    expect((await screen.findByRole("alert")).textContent).toBe("Mot de passe incorrect.");
  });

  it("leaves for the backoffice when 2FA is already on", async () => {
    server.use(sessionOf(true));
    renderWithProviders(<TwoFactorSetup />);

    await waitFor(() => expect(hardNavigate).toHaveBeenCalledWith("/"));
  });
});

async function waitForSentCode(sent: () => number): Promise<string> {
  await waitFor(() => expect(sent()).toBe(1));
  await screen.findByLabelText(/code reçu par e-mail/i);
  return "424242";
}
