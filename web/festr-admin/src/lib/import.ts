import { normalizeTime, resolveDay } from "./sets";

export interface DraftSet {
  artist: string;
  stage: string;
  day: string;
  start: string;
  end: string;
}

export interface DraftIssue {
  row: number;
  message: string;
}

const DELIMITERS = ["\t", "|", ";", ","];

function splitRow(line: string, delimiter: string): string[] {
  if (delimiter !== ",") return line.split(delimiter).map((c) => c.trim());
  const cells: string[] = [];
  let cell = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"' && line[i + 1] === '"' && quoted) {
      cell += '"';
      i++;
    } else if (ch === '"') {
      quoted = !quoted;
    } else if (ch === "," && !quoted) {
      cells.push(cell.trim());
      cell = "";
    } else {
      cell += ch;
    }
  }
  cells.push(cell.trim());
  return cells;
}

const COLUMNS = ["artist", "stage", "day", "start", "end"] as const;
type Column = (typeof COLUMNS)[number];

const ALIASES: Record<string, Column> = {
  artist: "artist",
  act: "artist",
  name: "artist",
  stage: "stage",
  day: "day",
  date: "day",
  start: "start",
  from: "start",
  begins: "start",
  end: "end",
  to: "end",
  until: "end",
  ends: "end",
};

/**
 * Parses pasted CSV/TSV rows: `artist, stage, day, start, end` (header optional, any column order with a header).
 * Days may be dates, weekday names or "Day N"; times may be 12- or 24-hour; an empty end is open-ended.
 */
export function parseSetsText(
  text: string,
  festivalDays: string[],
): { rows: DraftSet[]; issues: DraftIssue[] } {
  const lines = text.split(/\r?\n/).filter((line) => line.trim());
  if (lines.length === 0) return { rows: [], issues: [] };
  const delimiter = DELIMITERS.find((d) => lines[0].includes(d)) ?? ",";
  let order: Column[] = [...COLUMNS];
  const first = splitRow(lines[0], delimiter).map((c) => c.toLowerCase());
  if (first.some((c) => c in ALIASES && ALIASES[c] === "artist")) {
    order = first.map((c) => ALIASES[c]).filter(Boolean);
    lines.shift();
  }
  const rows: DraftSet[] = [];
  const issues: DraftIssue[] = [];
  lines.forEach((line, index) => {
    const cells = splitRow(line, delimiter);
    const get = (column: Column) => cells[order.indexOf(column)] ?? "";
    const { draft, problems } = normalizeDraft(
      { artist: get("artist"), stage: get("stage"), day: get("day"), start: get("start"), end: get("end") },
      festivalDays,
    );
    rows.push(draft);
    for (const message of problems) issues.push({ row: index + 1, message });
  });
  return { rows, issues };
}

/** Cleans one draft row; unresolvable values are kept as typed so the preview can show them. */
export function normalizeDraft(
  raw: DraftSet,
  festivalDays: string[],
): { draft: DraftSet; problems: string[] } {
  const problems: string[] = [];
  const artist = raw.artist.trim();
  if (!artist) problems.push("Missing artist");
  const day = resolveDay(raw.day, festivalDays);
  if (!day) problems.push(`Unknown day "${raw.day}"`);
  const start = normalizeTime(raw.start);
  if (!start) problems.push(`Bad start "${raw.start}"`);
  const endRaw = raw.end.trim();
  const end = endRaw && !/^(late|close|tbc|tba|open|-|–)$/i.test(endRaw) ? normalizeTime(endRaw) : "";
  if (end === null) problems.push(`Bad end "${raw.end}"`);
  return {
    draft: {
      artist,
      stage: raw.stage.trim(),
      day: day ?? raw.day.trim(),
      start: start ?? raw.start.trim(),
      end: end ?? endRaw,
    },
    problems,
  };
}
