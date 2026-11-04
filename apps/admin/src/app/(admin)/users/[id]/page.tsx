import { AuditHistory } from "@/features/audit/components/AuditHistory";
import { UserSheet } from "@/features/users/components/UserSheet";

/**
 * The user sheet (ADR-038 §5). The page composes features that may not import each other:
 * section 8 « Historique » is the Journal's `AuditHistory`. Section 6 « Premium » (#215) goes in
 * `premium`, and #214's « Supprimer le compte » in `extraActions`.
 */
export default async function UserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  return <UserSheet id={id} history={<AuditHistory subjectUserId={id} />} />;
}
