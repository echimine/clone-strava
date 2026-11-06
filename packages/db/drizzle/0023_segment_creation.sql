CREATE TABLE "segments"."segment_creation" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "segments"."segment_creation" ADD CONSTRAINT "segment_creation_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "segment_creation_user_created_idx" ON "segments"."segment_creation" USING btree ("user_id","created_at");--> statement-breakpoint
-- The creations still inside the quota window (hand-written).
INSERT INTO "segments"."segment_creation" ("user_id", "created_at") SELECT "created_by", "created_at" FROM "segments"."segment" WHERE "created_by" IS NOT NULL AND "created_at" > now() - interval '24 hours';
