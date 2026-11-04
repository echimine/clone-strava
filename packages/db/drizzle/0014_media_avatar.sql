-- ADR-037 §12: the only migration of the Media / Avatar / Gallery specs (#166, #167, #168).
-- Written by hand: drizzle-kit would ask whether these are renames. Nothing ever wrote to
-- `activity_attachment` nor `avatar_url`, so the renames carry no data to convert.
ALTER TYPE "activities"."attachment_kind" RENAME TO "media_kind";--> statement-breakpoint
ALTER TABLE "activities"."activity_attachment" RENAME TO "activity_media";--> statement-breakpoint
ALTER TABLE "activities"."activity_media" RENAME CONSTRAINT "activity_attachment_pkey" TO "activity_media_pkey";--> statement-breakpoint
ALTER TABLE "activities"."activity_media" RENAME CONSTRAINT "activity_attachment_activity_id_activity_id_fk" TO "activity_media_activity_id_activity_id_fk";--> statement-breakpoint
ALTER TABLE "activities"."activity_media" ADD COLUMN "width" integer NOT NULL;--> statement-breakpoint
ALTER TABLE "activities"."activity_media" ADD COLUMN "height" integer NOT NULL;--> statement-breakpoint
ALTER TABLE "activities"."activity_media" ADD COLUMN "duration_ms" integer;--> statement-breakpoint
CREATE INDEX "activity_media_activity_position_idx" ON "activities"."activity_media" USING btree ("activity_id","position","created_at");--> statement-breakpoint
ALTER TABLE "activities"."activity" ADD COLUMN "media_first" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "users"."user_profile" RENAME COLUMN "avatar_url" TO "avatar_key";
