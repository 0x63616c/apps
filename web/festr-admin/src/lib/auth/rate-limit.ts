export const MAX_ATTEMPTS = 5;
export const WINDOW_MS = 15 * 60 * 1000;

export interface AttemptRecord {
  attempts: number;
  resetAt: Date;
}

export interface AttemptStore {
  get(key: string): Promise<AttemptRecord | null>;
  set(key: string, record: AttemptRecord): Promise<void>;
  clear(key: string): Promise<void>;
}

/** Seconds until `keys` may try again, or 0 if none of them is locked out. */
export async function lockedFor(store: AttemptStore, keys: string[], now = Date.now()): Promise<number> {
  let wait = 0;
  for (const key of keys) {
    const record = await store.get(key);
    if (record && record.resetAt.getTime() > now && record.attempts >= MAX_ATTEMPTS) {
      wait = Math.max(wait, Math.ceil((record.resetAt.getTime() - now) / 1000));
    }
  }
  return wait;
}

export async function recordFailure(store: AttemptStore, keys: string[], now = Date.now()): Promise<void> {
  for (const key of keys) {
    const record = await store.get(key);
    const fresh = !record || record.resetAt.getTime() <= now;
    await store.set(key, {
      attempts: fresh ? 1 : record.attempts + 1,
      resetAt: fresh ? new Date(now + WINDOW_MS) : record.resetAt,
    });
  }
}

export async function clearFailures(store: AttemptStore, keys: string[]): Promise<void> {
  for (const key of keys) await store.clear(key);
}

export function memoryStore(): AttemptStore {
  const records = new Map<string, AttemptRecord>();
  return {
    get: async (key) => records.get(key) ?? null,
    set: async (key, record) => void records.set(key, record),
    clear: async (key) => void records.delete(key),
  };
}
