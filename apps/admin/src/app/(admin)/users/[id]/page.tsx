import { AuditHistory } from "@/features/audit/components/AuditHistory";
import { PremiumSection } from "@/features/premium/components/PremiumSection";
import { UserSheet } from "@/features/users/components/UserSheet";

/**
 * The user sheet (ADR-038 §5). The page composes features that may not import each other:
 * section 6 « Premium » is the Premium feature's `PremiumSection`, section 8 « Historique » the
 * Journal's `AuditHistory`. #214's « Supprimer le compte » goes in `extraActions`.
 */
export default async function UserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  return (
    <UserSheet id={id} premium={<PremiumSection userId={id} />} history={<AuditHistory subjectUserId={id} />} />
  );
}
