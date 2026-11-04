CREATE SCHEMA "moderation";
--> statement-breakpoint
CREATE TYPE "moderation"."report_case_status" AS ENUM('open', 'actioned', 'dismissed', 'target_gone');--> statement-breakpoint
CREATE TYPE "moderation"."report_reason" AS ENUM('spam', 'harassment', 'sexual_or_violent', 'impersonation', 'other');--> statement-breakpoint
CREATE TYPE "moderation"."report_target_type" AS ENUM('comment', 'activity', 'athlete');--> statement-breakpoint
CREATE TABLE "moderation"."report" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"case_id" uuid NOT NULL,
	"reporter_id" uuid,
	"reason" "moderation"."report_reason" NOT NULL,
	"note" text,
	"snapshot" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "report_reporter_case_unique" UNIQUE("reporter_id","case_id")
);
--> statement-breakpoint
CREATE TABLE "moderation"."report_case" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"target_type" "moderation"."report_target_type" NOT NULL,
	"target_id" uuid NOT NULL,
	"target_user_id" uuid NOT NULL,
	"status" "moderation"."report_case_status" DEFAULT 'open' NOT NULL,
	"opened_at" timestamp with time zone DEFAULT now() NOT NULL,
	"closed_at" timestamp with time zone,
	"closed_by" uuid,
	"close_note" text
);
--> statement-breakpoint
CREATE TABLE "social"."athlete_block" (
	"blocker_id" uuid NOT NULL,
	"blocked_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "athlete_block_blocker_id_blocked_id_pk" PRIMARY KEY("blocker_id","blocked_id"),
	CONSTRAINT "athlete_block_not_self_check" CHECK ("social"."athlete_block"."blocker_id" <> "social"."athlete_block"."blocked_id")
);
--> statement-breakpoint
ALTER TABLE "moderation"."report" ADD CONSTRAINT "report_case_id_report_case_id_fk" FOREIGN KEY ("case_id") REFERENCES "moderation"."report_case"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "moderation"."report" ADD CONSTRAINT "report_reporter_id_user_id_fk" FOREIGN KEY ("reporter_id") REFERENCES "public"."user"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "social"."athlete_block" ADD CONSTRAINT "athlete_block_blocker_id_user_id_fk" FOREIGN KEY ("blocker_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "social"."athlete_block" ADD CONSTRAINT "athlete_block_blocked_id_user_id_fk" FOREIGN KEY ("blocked_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "report_case_idx" ON "moderation"."report" USING btree ("case_id");--> statement-breakpoint
CREATE INDEX "report_reporter_created_at_idx" ON "moderation"."report" USING btree ("reporter_id","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "report_case_open_target_idx" ON "moderation"."report_case" USING btree ("target_type","target_id") WHERE "moderation"."report_case"."status" = 'open';--> statement-breakpoint
CREATE INDEX "report_case_status_opened_at_idx" ON "moderation"."report_case" USING btree ("status","opened_at");--> statement-breakpoint
CREATE INDEX "report_case_target_user_idx" ON "moderation"."report_case" USING btree ("target_user_id");--> statement-breakpoint
CREATE INDEX "athlete_block_blocked_idx" ON "social"."athlete_block" USING btree ("blocked_id");