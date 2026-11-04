import type { FeedAuthor } from "@repo/contracts";
import { Avatar, AvatarFallback, AvatarImage } from "@repo/ui/components/avatar";

/** Initials of a display name, « ? » without one. */
function initials(name: string): string {
  const letters = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word.charAt(0).toUpperCase())
    .join("");
  return letters || "?";
}

/** An athlete's Avatar (or initials), as the users list and sheet show it. */
export function UserAvatar({ athlete, className }: { athlete: FeedAuthor; className?: string }) {
  return (
    <Avatar className={className}>
      {athlete.avatarUrl ? <AvatarImage src={athlete.avatarUrl} alt="" /> : null}
      <AvatarFallback>{initials(athlete.displayName)}</AvatarFallback>
    </Avatar>
  );
}
