import "server-only";
import bcrypt from "bcryptjs";
import { eq } from "drizzle-orm";
import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { getDb } from "@/db";
import { loginAttempts } from "@/db/schema";
import type { AttemptStore } from "@/lib/auth/rate-limit";
import {
  newSession,
  SESSION_COOKIE,
  SESSION_TTL_SECONDS,
  sessionSecret,
  signSession,
  verifySession,
  type Session,
} from "@/lib/auth/session";

export const DEFAULT_ADMIN_EMAIL = "calumpeterwebb@icloud.com";

export function adminEmail(): string {
  return (process.env.ADMIN_EMAIL || DEFAULT_ADMIN_EMAIL).trim().toLowerCase();
}

/** Compared against even for unknown emails so response time doesn't reveal which part was wrong. */
const DUMMY_HASH = "$2b$12$jXhpcAqLcdow5hlHoKaQt.bYj0tXmibH05sjEV0CzNhoAA27sq7Wa";

export async function passwordMatches(email: string, password: string): Promise<boolean> {
  const hash = process.env.ADMIN_PASSWORD_HASH ?? "";
  const ok = await bcrypt.compare(password, hash.startsWith("$2") ? hash : DUMMY_HASH);
  return ok && hash.startsWith("$2") && email.trim().toLowerCase() === adminEmail();
}

export async function getSession(): Promise<Session | null> {
  const token = (await cookies()).get(SESSION_COOKIE)?.value;
  const session = await verifySession(token, sessionSecret());
  return session && session.sub === adminEmail() ? session : null;
}

/** Every page and server action behind the login calls this; the proxy redirect is only a convenience. */
export async function requireAdmin(): Promise<Session> {
  const session = await getSession();
  if (!session) redirect("/login");
  return session;
}

export async function startSession(email: string): Promise<void> {
  const token = await signSession(newSession(email.trim().toLowerCase()), sessionSecret());
  (await cookies()).set(SESSION_COOKIE, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: SESSION_TTL_SECONDS,
  });
}

export async function endSession(): Promise<void> {
  (await cookies()).delete(SESSION_COOKIE);
}

export async function clientIp(): Promise<string> {
  const h = await headers();
  return h.get("x-forwarded-for")?.split(",")[0]?.trim() || h.get("x-real-ip") || "unknown";
}

export const dbAttemptStore: AttemptStore = {
  async get(key) {
    const [row] = await getDb().select().from(loginAttempts).where(eq(loginAttempts.key, key));
    return row ? { attempts: row.attempts, resetAt: row.resetAt } : null;
  },
  async set(key, record) {
    await getDb()
      .insert(loginAttempts)
      .values({ key, ...record })
      .onConflictDoUpdate({ target: loginAttempts.key, set: record });
  },
  async clear(key) {
    await getDb().delete(loginAttempts).where(eq(loginAttempts.key, key));
  },
};
