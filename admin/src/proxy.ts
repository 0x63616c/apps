import { NextResponse, type NextRequest } from "next/server";
import { SESSION_COOKIE, verifySession } from "@/lib/auth/session";

/** Sends signed-out visitors to /login. Pages and actions still check the session themselves. */
export async function proxy(request: NextRequest) {
  const secret = process.env.SESSION_SECRET ?? "";
  const session =
    secret.length >= 32 ? await verifySession(request.cookies.get(SESSION_COOKIE)?.value, secret) : null;
  if (session) return NextResponse.next();
  const login = new URL("/login", request.url);
  const next = request.nextUrl.pathname + request.nextUrl.search;
  if (next !== "/") login.searchParams.set("next", next);
  return NextResponse.redirect(login);
}

export const config = {
  // The published feed must stay public for the iOS app.
  matcher: ["/((?!login|feed/|api/feed|_next/static|_next/image|favicon.ico|icon.svg).*)"],
};
