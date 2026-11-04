import { UsersView } from "@/features/users/components/UsersView";

export default function UsersPage() {
  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Utilisateurs</h1>
      <UsersView />
    </div>
  );
}
