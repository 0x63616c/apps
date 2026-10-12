CREATE TABLE "feed_files" (
	"path" text PRIMARY KEY NOT NULL,
	"body" text NOT NULL,
	"etag" text NOT NULL,
	"version" integer NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "login_attempts" (
	"key" text PRIMARY KEY NOT NULL,
	"attempts" integer DEFAULT 0 NOT NULL,
	"reset_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "publishes" (
	"version" serial PRIMARY KEY NOT NULL,
	"content_hash" text NOT NULL,
	"festival_count" integer NOT NULL,
	"set_count" integer NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "festivals" ADD COLUMN "website_url" text;--> statement-breakpoint
ALTER TABLE "festivals" ADD COLUMN "tickets_url" text;