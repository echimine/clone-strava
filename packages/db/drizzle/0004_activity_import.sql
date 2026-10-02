CREATE TYPE "activities"."activity_source" AS ENUM('recorded', 'imported', 'manual');--> statement-breakpoint
CREATE TYPE "activities"."import_format" AS ENUM('gpx', 'tcx', 'fit');--> statement-breakpoint
CREATE TYPE "activities"."import_status" AS ENUM('pending', 'processing', 'imported', 'duplicate', 'failed');--> statement-breakpoint
CREATE TABLE "activities"."activity_import" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"format" "activities"."import_format" NOT NULL,
	"original_file_name" text NOT NULL,
	"size_bytes" integer NOT NULL,
	"sha256" text,
	"status" "activities"."import_status" DEFAULT 'pending' NOT NULL,
	"activity_id" uuid,
	"requested_sport_type_code" text,
	"requested_title" text,
	"requested_visibility" "activities"."visibility",
	"error" text,
	"attempts" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"processed_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "activities"."activity" ADD COLUMN "source" "activities"."activity_source" DEFAULT 'recorded' NOT NULL;--> statement-breakpoint
ALTER TABLE "activities"."activity_import" ADD CONSTRAINT "activity_import_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activities"."activity_import" ADD CONSTRAINT "activity_import_activity_id_activity_id_fk" FOREIGN KEY ("activity_id") REFERENCES "activities"."activity"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activities"."activity_import" ADD CONSTRAINT "activity_import_requested_sport_type_code_sport_type_code_fk" FOREIGN KEY ("requested_sport_type_code") REFERENCES "sports"."sport_type"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "activity_import_user_created_at_idx" ON "activities"."activity_import" USING btree ("user_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE UNIQUE INDEX "activity_import_user_sha256_imported_idx" ON "activities"."activity_import" USING btree ("user_id","sha256") WHERE "activities"."activity_import"."status" = 'imported';--> statement-breakpoint
CREATE INDEX "activity_import_status_idx" ON "activities"."activity_import" USING btree ("status") WHERE "activities"."activity_import"."status" in ('pending', 'processing');