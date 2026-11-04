import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { SanctionDialog } from "./SanctionDialog";

function renderDialog(onConfirm = vi.fn(), extra?: { error?: string | null; isPending?: boolean }) {
  render(
    <SanctionDialog
      open
      onOpenChange={() => {}}
      title="Retirer le commentaire"
      summary="Le commentaire d'Émile sur « Sortie du dimanche » sera retiré."
      confirmLabel="Retirer"
      onConfirm={onConfirm}
      {...extra}
    />,
  );
  return onConfirm;
}

/** The shared Sanction dialog (ADR-038 §4): a required reason the athlete will read. */
describe("SanctionDialog", () => {
  it("summarizes the action and warns that the athlete reads the reason", () => {
    renderDialog();

    expect(screen.getByText("Le commentaire d'Émile sur « Sortie du dimanche » sera retiré.")).toBeTruthy();
    expect(screen.getByText("Ce motif sera lu par l'athlète.")).toBeTruthy();
  });

  it("cannot be confirmed without a reason", () => {
    const onConfirm = renderDialog();

    fireEvent.change(screen.getByLabelText("Motif"), { target: { value: "   " } });

    expect((screen.getByRole("button", { name: "Retirer" }) as HTMLButtonElement).disabled).toBe(true);
    expect(onConfirm).not.toHaveBeenCalled();
  });

  it("confirms with the reason, trimmed", async () => {
    const onConfirm = renderDialog();

    fireEvent.change(screen.getByLabelText("Motif"), { target: { value: "  Propos insultants  " } });
    fireEvent.click(screen.getByRole("button", { name: "Retirer" }));

    await waitFor(() => expect(onConfirm).toHaveBeenCalledWith("Propos insultants"));
  });

  it("shows why the action failed, and waits while it runs", () => {
    renderDialog(vi.fn(), { error: "Ce commentaire n'existe plus.", isPending: true });

    expect(screen.getByRole("alert").textContent).toBe("Ce commentaire n'existe plus.");
    expect((screen.getByRole("button", { name: "Retirer" }) as HTMLButtonElement).disabled).toBe(true);
  });
});
