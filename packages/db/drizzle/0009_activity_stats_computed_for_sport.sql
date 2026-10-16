ALTER TABLE "activities"."activity_stats" ADD COLUMN "computed_for_sport_type_code" text;--> statement-breakpoint
ALTER TABLE "activities"."activity_stats" ADD CONSTRAINT "activity_stats_computed_for_sport_type_code_sport_type_code_fk" FOREIGN KEY ("computed_for_sport_type_code") REFERENCES "sports"."sport_type"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
-- ADR-033 §5: existing official values were computed for the Activity's current sport.
UPDATE "activities"."activity_stats" AS s SET "computed_for_sport_type_code" = a."sport_type_code"
FROM "activities"."activity" AS a WHERE a."id" = s."activity_id";
