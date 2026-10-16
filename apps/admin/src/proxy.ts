import { NextResponse, type NextRequest } from "next/server";
import { getSessionCookie } from "better-auth/cookies";

/**
 * ADR-013 §"Authentication and authorization" step 1: without a session
 * cookie, redirect to `/login`. UI convenience only — the API remains the
 * sole guarantor of authorization (checked again in the `(admin)` layout
 * via `GET /v1/me`, and on every admin endpoint).
 */
export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const sessionCookie = getSessionCookie(request);

  if (!sessionCookie && !pathname.startsWith("/login")) {
    const loginUrl = new URL("/login", request.url);
    return NextResponse.redirect(loginUrl);
  }

  if (sessionCookie && pathname.startsWith("/login")) {
    return NextResponse.redirect(new URL("/", request.url));
  }

  return NextResponse.next();
}

/**
 * Public files are left out: the favicon (`app/icon.png`, served at
 * `/icon.png`) and `public/brand/*`, which emails load from clients that
 * never carry the session cookie (ADR-032 §2).
 */
export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon\\.ico|icon\\.png|brand/).*)"],
};
