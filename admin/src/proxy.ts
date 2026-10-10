import { NextResponse, type NextRequest } from "next/server";

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function unauthorized(message = "Authentication required"): NextResponse {
  return new NextResponse(message, {
    status: 401,
    headers: { "WWW-Authenticate": 'Basic realm="Festr Admin", charset="UTF-8"' },
  });
}

/** Basic auth for the admin UI. Any username is accepted; the password must equal ADMIN_PASSWORD. */
export function proxy(request: NextRequest) {
  const password = process.env.ADMIN_PASSWORD;
  if (!password) {
    if (process.env.NODE_ENV !== "production") return NextResponse.next();
    return new NextResponse("ADMIN_PASSWORD is not configured", { status: 503 });
  }

  const header = request.headers.get("authorization") ?? "";
  if (!header.startsWith("Basic ")) return unauthorized();
  let decoded: string;
  try {
    decoded = atob(header.slice(6));
  } catch {
    return unauthorized();
  }
  const supplied = decoded.slice(decoded.indexOf(":") + 1);
  return safeEqual(supplied, password) ? NextResponse.next() : unauthorized("Invalid credentials");
}

export const config = {
  // The public feed must stay reachable by the iOS app without credentials.
  matcher: ["/((?!api/feed|_next/static|_next/image|favicon.ico).*)"],
};
