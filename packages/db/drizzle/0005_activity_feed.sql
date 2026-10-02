ALTER TABLE "activities"."activity_track" ADD COLUMN "map_polyline" text;--> statement-breakpoint
ALTER TABLE "activities"."activity_track" ADD COLUMN "location_name" text;--> statement-breakpoint
-- ADR-029: backfill the feed polyline of already processed activities (~11 m tolerance).
-- New activities get an adaptive simplification from the worker; rows that still exceed
-- the static map budget are left null (the app shows a placeholder).
UPDATE "activities"."activity_track" AS t
SET "map_polyline" = p.polyline
FROM (
	SELECT "activity_id", ST_AsEncodedPolyline(ST_Simplify("route", 0.0001), 5) AS polyline
	FROM "activities"."activity_track"
	WHERE "route" IS NOT NULL
) AS p
WHERE t."activity_id" = p."activity_id" AND length(p.polyline) <= 2000;
