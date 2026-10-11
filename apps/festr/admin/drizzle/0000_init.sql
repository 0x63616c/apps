CREATE TABLE "festivals" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"venue" text NOT NULL,
	"city" text NOT NULL,
	"region" text NOT NULL,
	"country" text DEFAULT 'US' NOT NULL,
	"time_zone" text NOT NULL,
	"start_date" date NOT NULL,
	"end_date" date NOT NULL,
	"source_url" text,
	"lineup" text[] DEFAULT '{}'::text[] NOT NULL,
	"published" boolean DEFAULT true NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sets" (
	"id" text PRIMARY KEY NOT NULL,
	"festival_id" text NOT NULL,
	"stage_id" text NOT NULL,
	"artist" text NOT NULL,
	"day" date,
	"start_at" timestamp with time zone NOT NULL,
	"end_at" timestamp with time zone,
	"source_url" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "stages" (
	"id" text NOT NULL,
	"festival_id" text NOT NULL,
	"name" text NOT NULL,
	"sort_order" integer DEFAULT 0 NOT NULL,
	CONSTRAINT "stages_festival_id_id_pk" PRIMARY KEY("festival_id","id")
);
--> statement-breakpoint
ALTER TABLE "sets" ADD CONSTRAINT "sets_festival_id_festivals_id_fk" FOREIGN KEY ("festival_id") REFERENCES "public"."festivals"("id") ON DELETE cascade ON UPDATE cascade;--> statement-breakpoint
ALTER TABLE "sets" ADD CONSTRAINT "sets_stage_fk" FOREIGN KEY ("festival_id","stage_id") REFERENCES "public"."stages"("festival_id","id") ON DELETE cascade ON UPDATE cascade;--> statement-breakpoint
ALTER TABLE "stages" ADD CONSTRAINT "stages_festival_id_festivals_id_fk" FOREIGN KEY ("festival_id") REFERENCES "public"."festivals"("id") ON DELETE cascade ON UPDATE cascade;--> statement-breakpoint
CREATE INDEX "sets_festival_start_idx" ON "sets" USING btree ("festival_id","start_at");