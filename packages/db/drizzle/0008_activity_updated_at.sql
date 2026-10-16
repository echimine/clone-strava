ALTER TABLE "activities"."activity" ADD COLUMN "updated_at" timestamp with time zone DEFAULT now() NOT NULL;--> statement-breakpoint
-- ADR-033 §2: existing Activities start with `updated_at = created_at`.
UPDATE "activities"."activity" SET "updated_at" = "created_at";
