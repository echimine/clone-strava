import { BANNED_USER_CODE, type BannedUserError } from "@repo/contracts";

/** The admin plugin's Ban columns on `user` (ADR-017). */
export interface BanColumns {
  banned: boolean | null;
  banReason: string | null;
  banExpires: Date | null;
}

/** An active Ban: its end (null = permanent) and the reason the athlete reads. */
export interface ActiveBan {
  until: Date | null;
  reason: string | null;
}

/**
 * The Ban in force at `now` (ADR-038 §6): `banned and (ban_expires is null or ban_expires > now)`.
 * A Ban whose end has passed is over, even while the row keeps `banned = true` until the next
 * sign-in clears it.
 */
export function activeBan(columns: BanColumns, now: Date): ActiveBan | null {
  if (!columns.banned) {
    return null;
  }
  if (columns.banExpires && columns.banExpires.getTime() <= now.getTime()) {
    return null;
  }
  return { until: columns.banExpires, reason: columns.banReason };
}

const PARIS_DATE = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Europe/Paris",
  day: "numeric",
  month: "long",
  year: "numeric",
});
const PARIS_TIME = new Intl.DateTimeFormat("fr-FR", { timeZone: "Europe/Paris", hour: "2-digit", minute: "2-digit" });

/**
 * The body of the `403 BANNED_USER` a banned athlete's sign-in gets (ADR-038 §6): the end date or
 * « définitivement », the reason and the contact address, for the app's « Compte suspendu ».
 */
export function bannedUserError(columns: BanColumns, contactEmail: string | null): BannedUserError {
  const until = columns.banExpires;
  const message = until
    ? `Votre compte est suspendu jusqu'au ${PARIS_DATE.format(until)} à ${PARIS_TIME.format(until)}.`
    : "Votre compte est suspendu définitivement.";
  return {
    code: BANNED_USER_CODE,
    message,
    bannedUntil: until ? until.toISOString() : null,
    banReason: columns.banReason,
    contactEmail,
  };
}
