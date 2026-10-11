import bcrypt from "bcryptjs";
import { describe, expect, it } from "vitest";
import { clearFailures, lockedFor, MAX_ATTEMPTS, memoryStore, recordFailure, WINDOW_MS } from "./rate-limit";
import { newSession, signSession, verifySession } from "./session";

const secret = "x".repeat(40);

describe("session tokens", () => {
  it("round-trips a valid session", async () => {
    const session = newSession("calumpeterwebb@icloud.com", 1_000_000);
    const token = await signSession(session, secret);
    expect(await verifySession(token, secret, 1_000_000)).toEqual(session);
  });

  it("rejects tampered, foreign and expired tokens", async () => {
    const session = newSession("calumpeterwebb@icloud.com", 1_000_000);
    const token = await signSession(session, secret);
    const [, signature] = token.split(".");
    const forged = `${btoa(JSON.stringify({ ...session, sub: "x@y.z" })).replace(/=+$/, "")}.${signature}`;
    expect(await verifySession(forged, secret, 1_000_000)).toBeNull();
    expect(await verifySession(token, "y".repeat(40), 1_000_000)).toBeNull();
    expect(await verifySession(token, secret, session.exp * 1000 + 1)).toBeNull();
    expect(await verifySession("garbage", secret)).toBeNull();
    expect(await verifySession(undefined, secret)).toBeNull();
  });
});

describe("login rate limit", () => {
  it("locks a key after repeated failures and unlocks after the window", async () => {
    const store = memoryStore();
    const keys = ["ip:1.2.3.4", "email:a@b.c"];
    for (let i = 0; i < MAX_ATTEMPTS - 1; i++) await recordFailure(store, keys, 0);
    expect(await lockedFor(store, keys, 0)).toBe(0);
    await recordFailure(store, keys, 0);
    expect(await lockedFor(store, keys, 1000)).toBe(WINDOW_MS / 1000 - 1);
    expect(await lockedFor(store, keys, WINDOW_MS)).toBe(0);
    await recordFailure(store, keys, WINDOW_MS);
    expect(await lockedFor(store, keys, WINDOW_MS)).toBe(0);
  });

  it("clears on success", async () => {
    const store = memoryStore();
    for (let i = 0; i < MAX_ATTEMPTS; i++) await recordFailure(store, ["ip:x"], 0);
    await clearFailures(store, ["ip:x"]);
    expect(await lockedFor(store, ["ip:x"], 0)).toBe(0);
  });
});

describe("password hashes", () => {
  it("verifies bcrypt hashes produced by the hash script", async () => {
    const hash = await bcrypt.hash("correct horse", 4);
    expect(await bcrypt.compare("correct horse", hash)).toBe(true);
    expect(await bcrypt.compare("wrong", hash)).toBe(false);
  });
});
