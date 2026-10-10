import { asc, count, eq } from "drizzle-orm";
import Link from "next/link";
import { getDb } from "../db";
import { festivals, sets } from "../db/schema";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  const db = getDb();
  const rows = await db
    .select({
      id: festivals.id,
      name: festivals.name,
      city: festivals.city,
      region: festivals.region,
      startDate: festivals.startDate,
      endDate: festivals.endDate,
      published: festivals.published,
      setCount: count(sets.id),
    })
    .from(festivals)
    .leftJoin(sets, eq(sets.festivalId, festivals.id))
    .groupBy(festivals.id)
    .orderBy(asc(festivals.startDate), asc(festivals.id));

  return (
    <>
      <div className="actions" style={{ justifyContent: "space-between" }}>
        <h1>Festivals</h1>
        <Link href="/festivals/new">New festival</Link>
      </div>
      {rows.length === 0 ? (
        <p className="muted">No festivals yet. Create one, or run <code>pnpm db:seed</code>.</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Dates</th>
              <th>Location</th>
              <th>Sets</th>
              <th>Status</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {rows.map((f) => (
              <tr key={f.id}>
                <td>
                  {f.name}
                  <div className="muted">{f.id}</div>
                </td>
                <td>
                  {f.startDate} → {f.endDate}
                </td>
                <td>
                  {f.city}, {f.region}
                </td>
                <td>{f.setCount}</td>
                <td>
                  <span className="badge">{f.published ? "published" : "draft"}</span>
                </td>
                <td>
                  <Link href={`/festivals/${encodeURIComponent(f.id)}`}>Edit</Link>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  );
}
