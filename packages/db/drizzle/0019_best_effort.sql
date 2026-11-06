CREATE TYPE "activities"."medal" AS ENUM('gold', 'silver', 'bronze');--> statement-breakpoint
CREATE TYPE "activities"."record_set" AS ENUM('run', 'ride', 'walk', 'hike', 'swim_pool', 'swim_open_water');--> statement-breakpoint
CREATE TABLE "activities"."best_effort" (
	"activity_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"record_set" "activities"."record_set" NOT NULL,
	"distance_m" double precision NOT NULL,
	"elapsed_time_ms" integer NOT NULL,
	"start_distance_m" real NOT NULL,
	"activity_started_at" timestamp with time zone NOT NULL,
	"medal" "activities"."medal",
	"removed_at" timestamp with time zone,
	CONSTRAINT "best_effort_activity_id_distance_m_pk" PRIMARY KEY("activity_id","distance_m")
);
--> statement-breakpoint
ALTER TABLE "activities"."best_effort" ADD CONSTRAINT "best_effort_activity_id_activity_id_fk" FOREIGN KEY ("activity_id") REFERENCES "activities"."activity"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activities"."best_effort" ADD CONSTRAINT "best_effort_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "best_effort_user_set_distance_time_idx" ON "activities"."best_effort" USING btree ("user_id","record_set","distance_m","elapsed_time_ms");