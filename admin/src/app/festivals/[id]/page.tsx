import { asc, eq } from "drizzle-orm";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getDb } from "../../../db";
import { festivals, sets, stages, type SetRow, type StageRow } from "../../../db/schema";
import { formatInZone } from "../../../lib/time";
import { addStage, deleteFestival, deleteSet, deleteStage, saveSet, updateStage } from "../../actions";
import { FestivalForm } from "../../festival-form";

export const dynamic = "force-dynamic";

function weekday(date: string): string {
  return new Date(`${date}T12:00:00Z`).toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  });
}

function SetForm({
  festivalId,
  timeZone,
  stageList,
  set,
  defaultDate,
}: {
  festivalId: string;
  timeZone: string;
  stageList: StageRow[];
  set?: SetRow;
  defaultDate: string;
}) {
  const start = set ? formatInZone(set.startAt, timeZone) : null;
  const end = set?.endAt ? formatInZone(set.endAt, timeZone) : null;
  return (
    <form action={saveSet} className="grid">
      <input type="hidden" name="festivalId" value={festivalId} />
      <input type="hidden" name="setId" value={set?.id ?? ""} />
      <label>
        Artist
        <input name="artist" defaultValue={set?.artist} required />
      </label>
      <label>
        Stage
        <select name="stageId" defaultValue={set?.stageId ?? stageList[0]?.id} required>
          {stageList.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </select>
      </label>
      <label>
        Start date (local)
        <input type="date" name="date" defaultValue={start?.date ?? defaultDate} required />
      </label>
      <label>
        Start time (local)
        <input type="time" name="startTime" defaultValue={start?.time} required />
      </label>
      <label>
        End time (local, blank = open end)
        <input type="time" name="endTime" defaultValue={end?.time ?? ""} />
      </label>
      <label>
        Festival day (blank = start date)
        <input type="date" name="day" defaultValue={set?.day ?? ""} />
      </label>
      {!set && (
        <label>
          ID (optional)
          <input name="id" pattern="[a-z0-9][a-z0-9\-]*" placeholder="auto" />
        </label>
      )}
      <label className="wide">
        Source URL
        <input type="url" name="sourceUrl" defaultValue={set?.sourceUrl ?? ""} />
      </label>
      <div className="wide muted">
        Times are wall-clock in {timeZone}. An end time earlier than the start means the set ends after
        midnight (next day).
      </div>
      <div className="wide">
        <button type="submit">{set ? "Save set" : "Add set"}</button>
      </div>
    </form>
  );
}

export default async function FestivalPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ error?: string }>;
}) {
  const { id } = await params;
  const { error } = await searchParams;
  const db = getDb();
  const [festival] = await db.select().from(festivals).where(eq(festivals.id, id));
  if (!festival) notFound();

  const [stageList, setList] = await Promise.all([
    db.select().from(stages).where(eq(stages.festivalId, id)).orderBy(asc(stages.sortOrder), asc(stages.id)),
    db.select().from(sets).where(eq(sets.festivalId, id)).orderBy(asc(sets.startAt), asc(sets.stageId)),
  ]);
  const stageName = new Map(stageList.map((s) => [s.id, s.name]));
  const tz = festival.timeZone;

  const byDay = new Map<string, SetRow[]>();
  for (const s of setList) {
    const key = s.day ?? formatInZone(s.startAt, tz).date;
    byDay.set(key, [...(byDay.get(key) ?? []), s]);
  }

  return (
    <>
      <p>
        <Link href="/">← Festivals</Link>
      </p>
      <h1>
        {festival.name} <span className="badge">{festival.published ? "published" : "draft"}</span>
      </h1>
      {error && <p className="error">{error}</p>}

      <h2>Festival</h2>
      <FestivalForm festival={festival} />

      <h2>Stages</h2>
      {stageList.map((s) => (
        <div key={s.id} className="actions">
          <form action={updateStage} className="row">
            <input type="hidden" name="festivalId" value={id} />
            <input type="hidden" name="stageId" value={s.id} />
            <label>
              ID
              <input value={s.id} disabled size={12} />
            </label>
            <label>
              Name
              <input name="name" defaultValue={s.name} required />
            </label>
            <label>
              Sort
              <input type="number" name="sortOrder" defaultValue={s.sortOrder} style={{ width: "5rem" }} />
            </label>
            <button type="submit" className="secondary">
              Save
            </button>
          </form>
          <form action={deleteStage}>
            <input type="hidden" name="festivalId" value={id} />
            <input type="hidden" name="stageId" value={s.id} />
            <button type="submit" className="danger" title="Also deletes this stage's sets">
              Delete
            </button>
          </form>
        </div>
      ))}
      <form action={addStage} className="row">
        <input type="hidden" name="festivalId" value={id} />
        <label>
          New stage name
          <input name="name" required />
        </label>
        <label>
          ID (optional)
          <input name="id" pattern="[a-z0-9][a-z0-9\-]*" placeholder="auto from name" size={14} />
        </label>
        <label>
          Sort
          <input type="number" name="sortOrder" placeholder="auto" style={{ width: "5rem" }} />
        </label>
        <button type="submit">Add stage</button>
      </form>
      <p className="muted">Deleting a stage also deletes its sets.</p>

      <h2>Sets ({setList.length})</h2>
      {stageList.length === 0 ? (
        <p className="muted">Add a stage before adding sets.</p>
      ) : (
        <>
          <details>
            <summary>
              <strong>Add set</strong>
            </summary>
            <SetForm festivalId={id} timeZone={tz} stageList={stageList} defaultDate={festival.startDate} />
          </details>
          {[...byDay.entries()].map(([day, daySets]) => (
            <div key={day}>
              <div className="day-heading">{weekday(day)}</div>
              {daySets.map((s) => {
                const start = formatInZone(s.startAt, tz);
                const end = s.endAt ? formatInZone(s.endAt, tz) : null;
                return (
                  <details key={s.id} className="set">
                    <summary>
                      <span>
                        {start.time}–{end ? end.time : "close"}
                        {end && end.date !== start.date ? " (+1)" : ""}
                        {start.date !== day ? ` · ${weekday(start.date)}` : ""}
                      </span>
                      <span className="muted">{stageName.get(s.stageId) ?? s.stageId}</span>
                      <span>{s.artist}</span>
                    </summary>
                    <SetForm festivalId={id} timeZone={tz} stageList={stageList} set={s} defaultDate={day} />
                    <form action={deleteSet} className="row">
                      <input type="hidden" name="festivalId" value={id} />
                      <input type="hidden" name="setId" value={s.id} />
                      <span className="muted">{s.id}</span>
                      <button type="submit" className="danger">
                        Delete set
                      </button>
                    </form>
                  </details>
                );
              })}
            </div>
          ))}
        </>
      )}

      <h2>Danger zone</h2>
      <form action={deleteFestival}>
        <input type="hidden" name="festivalId" value={id} />
        <button type="submit" className="danger">
          Delete festival (and all stages and sets)
        </button>
      </form>
    </>
  );
}
