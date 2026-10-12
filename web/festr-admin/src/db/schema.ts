import { sql } from "drizzle-orm";
import {
  boolean,
  date,
  foreignKey,
  index,
  integer,
  pgTable,
  primaryKey,
  serial,
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
  websiteUrl: text("website_url"),
  ticketsUrl: text("tickets_url"),
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

/** Files served under /feed/, written only by Publish. */
export const feedFiles = pgTable("feed_files", {
  path: text("path").primaryKey(),
  body: text("body").notNull(),
  etag: text("etag").notNull(),
  version: integer("version").notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
});

export const publishes = pgTable("publishes", {
  version: serial("version").primaryKey(),
  contentHash: text("content_hash").notNull(),
  festivalCount: integer("festival_count").notNull(),
  setCount: integer("set_count").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
});

/** Failed login attempts per key (ip:… or email:…), shared across serverless instances. */
export const loginAttempts = pgTable("login_attempts", {
  key: text("key").primaryKey(),
  attempts: integer("attempts").notNull().default(0),
  resetAt: timestamp("reset_at", { withTimezone: true, mode: "date" }).notNull(),
});

export type FestivalRow = typeof festivals.$inferSelect;
export type StageRow = typeof stages.$inferSelect;
export type SetRow = typeof sets.$inferSelect;
