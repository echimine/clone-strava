/**
 * Full page navigation, outside React (no router there). Also used on
 * purpose after a sign-in, a sign-out or a 2FA change: the reload drops the
 * whole TanStack Query cache of the previous session.
 */
export function hardNavigate(url: string): void {
  window.location.assign(url);
}
