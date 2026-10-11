import { addDays, formatInZone, isValidDate, localSetTimesToUtc } from "./time";

/** Matches the iOS app: a set starting before 06:00 belongs to the previous festival day. */
export const DAY_ROLLOVER_HOUR = 6;

const TIME_RE = /^(\d{1,2})(?::|\.|h)?(\d{2})?\s*(am|pm|a|p)?$/i;

/** Normalises "9:10 PM", "21.10", "2110", "9pm" to "HH:MM"; returns null when unparseable. */
export function normalizeTime(raw: string): string | null {
  const value = raw.trim().toLowerCase().replace(/\s+/g, " ");
  if (!value) return null;
  const compact = /^\d{3,4}$/.test(value) ? `${value.slice(0, -2)}:${value.slice(-2)}` : value;
  const m = TIME_RE.exec(compact.replace(" ", ""));
  if (!m) return null;
  let hour = Number(m[1]);
  const minute = Number(m[2] ?? 0);
  const meridiem = m[3]?.[0];
  if (minute > 59) return null;
  if (meridiem) {
    if (hour < 1 || hour > 12) return null;
    hour = (hour % 12) + (meridiem === "p" ? 12 : 0);
  }
  if (hour > 23) return null;
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

/** Local calendar date a set on festival `day` starting at `start` actually begins. */
export function startDateFor(day: string, start: string): string {
  return Number(start.slice(0, 2)) < DAY_ROLLOVER_HOUR ? addDays(day, 1) : day;
}

export interface SetTimesInput {
  day: string;
  start: string;
  end: string | null;
  timeZone: string;
}

export function setInstants({ day, start, end, timeZone }: SetTimesInput): {
  startAt: Date;
  endAt: Date | null;
} {
  if (!isValidDate(day)) throw new Error(`Invalid day "${day}"`);
  return localSetTimesToUtc({ date: startDateFor(day, start), startTime: start, endTime: end, timeZone });
}

/** Local "HH:MM" start and end for display and editing. */
export function localTimes(set: { startAt: Date; endAt: Date | null }, timeZone: string) {
  return {
    start: formatInZone(set.startAt, timeZone).time,
    end: set.endAt ? formatInZone(set.endAt, timeZone).time : null,
  };
}

/** Festival days, inclusive. */
export function festivalDays(startDate: string, endDate: string): string[] {
  const days: string[] = [];
  for (let day = startDate; day <= endDate && days.length < 31; day = addDays(day, 1)) days.push(day);
  return days;
}

const WEEKDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

export function weekdayOf(day: string): number {
  const [y, m, d] = day.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

/** Resolves "2026-10-10", "Sat", "Saturday" or "Day 1" against the festival's days. */
export function resolveDay(raw: string, days: string[]): string | null {
  const value = raw.trim().toLowerCase();
  if (!value) return days.length === 1 ? days[0] : null;
  if (isValidDate(value)) return value;
  const dayNumber = /^day\s*(\d+)$/.exec(value);
  if (dayNumber) return days[Number(dayNumber[1]) - 1] ?? null;
  const weekday = WEEKDAYS.findIndex((name) => name.startsWith(value.slice(0, 3)) && name.startsWith(value));
  if (weekday === -1) return null;
  return days.find((day) => weekdayOf(day) === weekday) ?? null;
}
