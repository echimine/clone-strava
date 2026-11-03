-- ADR-036 §2: accent-insensitive athlete search (`unaccent` + `ILIKE`). Added by hand,
-- like `postgis` in 0000 (drizzle-kit does not generate extensions).
CREATE EXTENSION IF NOT EXISTS unaccent;--> statement-breakpoint
CREATE TABLE "activities"."activity_analysis" (
	"activity_id" uuid PRIMARY KEY NOT NULL,
	"version" smallint NOT NULL,
	"splits" jsonb NOT NULL,
	"series" jsonb,
	"computed_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "social"."follow_settings" (
	"user_id" uuid PRIMARY KEY NOT NULL,
	"approve_followers" boolean DEFAULT false NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "activities"."activity_track" ADD COLUMN "route_trimmed" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "activities"."activity_analysis" ADD CONSTRAINT "activity_analysis_activity_id_activity_id_fk" FOREIGN KEY ("activity_id") REFERENCES "activities"."activity"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "social"."follow_settings" ADD CONSTRAINT "follow_settings_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "follow_follower_status_idx" ON "social"."follow" USING btree ("follower_id","status");--> statement-breakpoint
ALTER TABLE "social"."follow" ADD CONSTRAINT "follow_not_self_check" CHECK ("social"."follow"."follower_id" <> "social"."follow"."followee_id");