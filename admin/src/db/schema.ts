import { sql } from "drizzle-orm";
import {
  boolean,
  date,
  foreignKey,
  index,
  integer,
  pgTable,
  primaryKey,
  text,
  timestamp,
} from "drizzle-orm/pg-core";

export const festivals = pgTable("festivals", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  venue: text("venue").notNull(),
  city: text("city").notNull(),
  region: text("region").notNull(),
  country: text("country").notNull().default("US"),
  timeZone: text("time_zone").notNull(),
  startDate: date("start_date", { mode: "string" }).notNull(),
  endDate: date("end_date", { mode: "string" }).notNull(),
  sourceUrl: text("source_url"),
  lineup: text("lineup")
    .array()
    .notNull()
    .default(sql`'{}'::text[]`),
  published: boolean("published").notNull().default(true),
  updatedAt: timestamp("updated_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
});

export const stages = pgTable(
  "stages",
  {
    id: text("id").notNull(),
    festivalId: text("festival_id")
      .notNull()
      .references(() => festivals.id, { onDelete: "cascade", onUpdate: "cascade" }),
    name: text("name").notNull(),
    sortOrder: integer("sort_order").notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.festivalId, t.id] })],
);

export const sets = pgTable(
  "sets",
  {
    id: text("id").primaryKey(),
    festivalId: text("festival_id")
      .notNull()
      .references(() => festivals.id, { onDelete: "cascade", onUpdate: "cascade" }),
    stageId: text("stage_id").notNull(),
    artist: text("artist").notNull(),
    day: date("day", { mode: "string" }),
    startAt: timestamp("start_at", { withTimezone: true, mode: "date" }).notNull(),
    endAt: timestamp("end_at", { withTimezone: true, mode: "date" }),
    sourceUrl: text("source_url"),
    updatedAt: timestamp("updated_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  },
  (t) => [
    foreignKey({
      columns: [t.festivalId, t.stageId],
      foreignColumns: [stages.festivalId, stages.id],
      name: "sets_stage_fk",
    })
      .onDelete("cascade")
      .onUpdate("cascade"),
    index("sets_festival_start_idx").on(t.festivalId, t.startAt),
  ],
);

export type FestivalRow = typeof festivals.$inferSelect;
export type StageRow = typeof stages.$inferSelect;
export type SetRow = typeof sets.$inferSelect;
