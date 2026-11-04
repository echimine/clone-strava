CREATE SCHEMA "audit";
--> statement-breakpoint
CREATE TABLE "audit"."admin_audit_entry" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"actor_id" uuid,
	"action" text NOT NULL,
	"target_type" text NOT NULL,
	"target_id" text,
	"subject_user_id" uuid,
	"reason" text,
	"details" jsonb,
	"request_id" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE INDEX "admin_audit_entry_subject_created_at_idx" ON "audit"."admin_audit_entry" USING btree ("subject_user_id","created_at");--> statement-breakpoint
CREATE INDEX "admin_audit_entry_actor_created_at_idx" ON "audit"."admin_audit_entry" USING btree ("actor_id","created_at");--> statement-breakpoint
CREATE INDEX "admin_audit_entry_action_created_at_idx" ON "audit"."admin_audit_entry" USING btree ("action","created_at");