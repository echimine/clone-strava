CREATE TYPE "segments"."climb_category" AS ENUM('hc', '1', '2', '3', '4');--> statement-breakpoint
CREATE TYPE "segments"."effort_medal" AS ENUM('gold', 'silver', 'bronze');--> statement-breakpoint
CREATE TYPE "segments"."effort_status" AS ENUM('valid', 'suspicious', 'rejected');--> statement-breakpoint
CREATE TYPE "segments"."segment_origin" AS ENUM('athlete', 'nervo');--> statement-breakpoint
CREATE TABLE "segments"."activity_matching" (
	"activity_id" uuid PRIMARY KEY NOT NULL,
	"version" integer NOT NULL,
	"matched_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "segments"."excluded_source_key" (
	"source_key" text PRIMARY KEY NOT NULL,
	"excluded_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "segments"."segment_favorite" (
	"user_id" uuid NOT NULL,
	"segment_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "segment_favorite_user_id_segment_id_pk" PRIMARY KEY("user_id","segment_id")
);
--> statement-breakpoint
-- ADR-039 §6: no Effort was ever matched (the job threw); the reconciliation matches every Activity again.
DELETE FROM "segments"."segment_effort";--> statement-breakpoint
DROP INDEX "segments"."segment_effort_segment_elapsed_time_idx";--> statement-breakpoint
ALTER TABLE "segments"."segment" ALTER COLUMN "path" SET DATA TYPE geometry(LineStringZ,4326) USING ST_Force3DZ("path");--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "created_by" uuid;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "origin" "segments"."segment_origin" DEFAULT 'athlete' NOT NULL;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "source_key" text;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "verified_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "max_grade" real;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "elevation_gain_m" real;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "min_altitude_m" real;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "max_altitude_m" real;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "climb_category" "segments"."climb_category";--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "map_polyline" text;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "history_matched_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "created_at" timestamp with time zone DEFAULT now() NOT NULL;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD COLUMN "updated_at" timestamp with time zone DEFAULT now() NOT NULL;--> statement-breakpoint
ALTER TABLE "segments"."segment_effort" ADD COLUMN "start_index" integer NOT NULL;--> statement-breakpoint
ALTER TABLE "segments"."segment_effort" ADD COLUMN "end_index" integer NOT NULL;--> statement-breakpoint
ALTER TABLE "segments"."segment_effort" ADD COLUMN "min_distance_to_activity_start_m" real NOT NULL;--> statement-breakpoint
ALTER TABLE "segments"."segment_effort" ADD COLUMN "min_distance_to_activity_end_m" real NOT NULL;--> statement-breakpoint
ALTER TABLE "segments"."segment_effort" ADD COLUMN "status" "segments"."effort_status" DEFAULT 'valid' NOT NULL;--> statement-breakpoint
ALTER TABLE "segments"."segment_effort" ADD COLUMN "medal" "segments"."effort_medal";--> statement-breakpoint
ALTER TABLE "segments"."activity_matching" ADD CONSTRAINT "activity_matching_activity_id_activity_id_fk" FOREIGN KEY ("activity_id") REFERENCES "activities"."activity"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "segments"."segment_favorite" ADD CONSTRAINT "segment_favorite_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "segments"."segment_favorite" ADD CONSTRAINT "segment_favorite_segment_id_segment_id_fk" FOREIGN KEY ("segment_id") REFERENCES "segments"."segment"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD CONSTRAINT "segment_created_by_user_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."user"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "segment_end_point_gist_idx" ON "segments"."segment" USING gist ("end_point");--> statement-breakpoint
CREATE UNIQUE INDEX "segment_effort_activity_segment_start_idx" ON "segments"."segment_effort" USING btree ("activity_id","segment_id","start_index");--> statement-breakpoint
CREATE INDEX "segment_effort_segment_status_time_idx" ON "segments"."segment_effort" USING btree ("segment_id","status","elapsed_time_s");--> statement-breakpoint
CREATE INDEX "segment_effort_user_segment_started_at_idx" ON "segments"."segment_effort" USING btree ("user_id","segment_id","started_at");--> statement-breakpoint
ALTER TABLE "segments"."segment_effort" DROP COLUMN "rank";--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD CONSTRAINT "segment_source_key_unique" UNIQUE("source_key");--> statement-breakpoint
CREATE VIEW "activities"."leaderboard_activity" AS (select "id", "user_id", "sport_type_code", "visibility" from "activities"."activity" where "activities"."activity"."processing_status" = 'processed');--> statement-breakpoint
CREATE VIEW "users"."leaderboard_athlete" AS (select "user_id", "gender", "birth_date", "weight_kg", "privacy_zone_radius_m" from "users"."user_profile");