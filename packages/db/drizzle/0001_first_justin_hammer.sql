CREATE SCHEMA "activities";
--> statement-breakpoint
CREATE SCHEMA "engagement";
--> statement-breakpoint
CREATE SCHEMA "segments";
--> statement-breakpoint
CREATE SCHEMA "social";
--> statement-breakpoint
CREATE SCHEMA "sports";
--> statement-breakpoint
CREATE SCHEMA "subscriptions";
--> statement-breakpoint
CREATE SCHEMA "users";
--> statement-breakpoint
CREATE TYPE "activities"."visibility" AS ENUM('public', 'followers', 'private');--> statement-breakpoint
CREATE TYPE "activities"."attachment_kind" AS ENUM('photo', 'video');--> statement-breakpoint
CREATE TYPE "activities"."processing_status" AS ENUM('pending', 'processing', 'processed', 'failed');--> statement-breakpoint
CREATE TYPE "public"."user_role" AS ENUM('user', 'admin');--> statement-breakpoint
CREATE TYPE "social"."follow_status" AS ENUM('pending', 'accepted');--> statement-breakpoint
CREATE TYPE "sports"."pace_unit" AS ENUM('pace', 'speed');--> statement-breakpoint
CREATE TYPE "subscriptions"."environment" AS ENUM('sandbox', 'production');--> statement-breakpoint
CREATE TYPE "subscriptions"."period_type" AS ENUM('trial', 'intro', 'normal');--> statement-breakpoint
CREATE TYPE "subscriptions"."store" AS ENUM('app_store');--> statement-breakpoint
CREATE TYPE "users"."visibility" AS ENUM('public', 'followers', 'private');--> statement-breakpoint
CREATE TYPE "users"."unit_system" AS ENUM('metric', 'imperial');--> statement-breakpoint
CREATE TABLE "activities"."activity" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"sport_type_code" text NOT NULL,
	"title" text NOT NULL,
	"description" text,
	"started_at" timestamp with time zone NOT NULL,
	"ended_at" timestamp with time zone NOT NULL,
	"visibility" "activities"."visibility" DEFAULT 'public' NOT NULL,
	"processing_status" "activities"."processing_status" DEFAULT 'pending' NOT NULL,
	"is_manual" boolean DEFAULT false NOT NULL,
	"processing_error" text,
	"processing_attempts" integer DEFAULT 0 NOT NULL,
	"processed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "activities"."activity_attachment" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"activity_id" uuid NOT NULL,
	"s3_key" text NOT NULL,
	"kind" "activities"."attachment_kind" NOT NULL,
	"position" integer DEFAULT 0 NOT NULL,
	"taken_at_point" geometry(Point,4326),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "activities"."activity_stats" (
	"activity_id" uuid PRIMARY KEY NOT NULL,
	"distance_m" real,
	"moving_time_s" integer,
	"elapsed_time_s" integer,
	"elevation_gain_m" real,
	"avg_speed_ms" real,
	"max_speed_ms" real,
	"avg_heart_rate" integer,
	"max_heart_rate" integer,
	"calories" integer
);
--> statement-breakpoint
CREATE TABLE "activities"."activity_track" (
	"activity_id" uuid PRIMARY KEY NOT NULL,
	"route" geometry(LineString,4326),
	"start_point" geometry(Point,4326),
	"raw_points_s3_key" text,
	"map_thumbnail_url" text,
	"point_count" integer
);
--> statement-breakpoint
CREATE TABLE "account" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"account_id" text NOT NULL,
	"provider_id" text NOT NULL,
	"access_token" text,
	"refresh_token" text,
	"id_token" text,
	"access_token_expires_at" timestamp with time zone,
	"refresh_token_expires_at" timestamp with time zone,
	"scope" text,
	"password" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "session" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"token" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"ip_address" text,
	"user_agent" text,
	"impersonated_by" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "session_token_unique" UNIQUE("token")
);
--> statement-breakpoint
CREATE TABLE "user" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"email" text NOT NULL,
	"email_verified" boolean DEFAULT false NOT NULL,
	"image" text,
	"role" "user_role" DEFAULT 'user' NOT NULL,
	"banned" boolean DEFAULT false NOT NULL,
	"ban_reason" text,
	"ban_expires" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "user_email_unique" UNIQUE("email")
);
--> statement-breakpoint
CREATE TABLE "verification" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"identifier" text NOT NULL,
	"value" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "engagement"."comment" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"activity_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"body" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "engagement"."kudos" (
	"user_id" uuid NOT NULL,
	"activity_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "kudos_user_id_activity_id_pk" PRIMARY KEY("user_id","activity_id")
);
--> statement-breakpoint
CREATE TABLE "segments"."segment" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"sport_type_code" text NOT NULL,
	"path" geometry(LineString,4326),
	"start_point" geometry(Point,4326),
	"end_point" geometry(Point,4326),
	"distance_m" real,
	"avg_grade" real
);
--> statement-breakpoint
CREATE TABLE "segments"."segment_effort" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"activity_id" uuid NOT NULL,
	"segment_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"elapsed_time_s" integer NOT NULL,
	"started_at" timestamp with time zone NOT NULL,
	"rank" integer
);
--> statement-breakpoint
CREATE TABLE "social"."follow" (
	"follower_id" uuid NOT NULL,
	"followee_id" uuid NOT NULL,
	"status" "social"."follow_status" DEFAULT 'pending' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "follow_follower_id_followee_id_pk" PRIMARY KEY("follower_id","followee_id")
);
--> statement-breakpoint
CREATE TABLE "sports"."sport_type" (
	"code" text PRIMARY KEY NOT NULL,
	"category" text NOT NULL,
	"icon_name" text NOT NULL,
	"tracks_distance" boolean DEFAULT true NOT NULL,
	"tracks_elevation" boolean DEFAULT true NOT NULL,
	"uses_gps" boolean DEFAULT true NOT NULL,
	"pace_unit" "sports"."pace_unit" DEFAULT 'pace' NOT NULL,
	"min_duration_s" integer DEFAULT 60 NOT NULL,
	"min_distance_m" integer DEFAULT 0 NOT NULL,
	"display_order" integer DEFAULT 0 NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL
);
--> statement-breakpoint
CREATE TABLE "subscriptions"."revenuecat_event" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" uuid,
	"type" text NOT NULL,
	"payload" jsonb NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL,
	"processed_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "subscriptions"."user_subscription" (
	"user_id" uuid NOT NULL,
	"entitlement_id" text DEFAULT 'premium' NOT NULL,
	"is_active" boolean DEFAULT false NOT NULL,
	"product_id" text,
	"store" "subscriptions"."store",
	"period_type" "subscriptions"."period_type",
	"will_renew" boolean DEFAULT false NOT NULL,
	"purchased_at" timestamp with time zone,
	"expires_at" timestamp with time zone,
	"grace_period_expires_at" timestamp with time zone,
	"billing_issue_detected_at" timestamp with time zone,
	"unsubscribe_detected_at" timestamp with time zone,
	"environment" "subscriptions"."environment",
	"synced_at" timestamp with time zone,
	CONSTRAINT "user_subscription_user_id_entitlement_id_pk" PRIMARY KEY("user_id","entitlement_id")
);
--> statement-breakpoint
CREATE TABLE "users"."user_profile" (
	"user_id" uuid PRIMARY KEY NOT NULL,
	"first_name" text,
	"last_name" text,
	"avatar_url" text,
	"country" text,
	"city" text,
	"birth_date" date,
	"gender" text,
	"weight_kg" real,
	"unit_system" "users"."unit_system" DEFAULT 'metric' NOT NULL,
	"default_visibility" "users"."visibility" DEFAULT 'public' NOT NULL,
	"privacy_zone_radius_m" integer DEFAULT 200 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "activities"."activity" ADD CONSTRAINT "activity_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activities"."activity" ADD CONSTRAINT "activity_sport_type_code_sport_type_code_fk" FOREIGN KEY ("sport_type_code") REFERENCES "sports"."sport_type"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activities"."activity_attachment" ADD CONSTRAINT "activity_attachment_activity_id_activity_id_fk" FOREIGN KEY ("activity_id") REFERENCES "activities"."activity"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activities"."activity_stats" ADD CONSTRAINT "activity_stats_activity_id_activity_id_fk" FOREIGN KEY ("activity_id") REFERENCES "activities"."activity"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activities"."activity_track" ADD CONSTRAINT "activity_track_activity_id_activity_id_fk" FOREIGN KEY ("activity_id") REFERENCES "activities"."activity"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "account" ADD CONSTRAINT "account_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "session" ADD CONSTRAINT "session_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "session" ADD CONSTRAINT "session_impersonated_by_user_id_fk" FOREIGN KEY ("impersonated_by") REFERENCES "public"."user"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "engagement"."comment" ADD CONSTRAINT "comment_activity_id_activity_id_fk" FOREIGN KEY ("activity_id") REFERENCES "activities"."activity"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "engagement"."comment" ADD CONSTRAINT "comment_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "engagement"."kudos" ADD CONSTRAINT "kudos_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "engagement"."kudos" ADD CONSTRAINT "kudos_activity_id_activity_id_fk" FOREIGN KEY ("activity_id") REFERENCES "activities"."activity"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "segments"."segment" ADD CONSTRAINT "segment_sport_type_code_sport_type_code_fk" FOREIGN KEY ("sport_type_code") REFERENCES "sports"."sport_type"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "segments"."segment_effort" ADD CONSTRAINT "segment_effort_activity_id_activity_id_fk" FOREIGN KEY ("activity_id") REFERENCES "activities"."activity"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "segments"."segment_effort" ADD CONSTRAINT "segment_effort_segment_id_segment_id_fk" FOREIGN KEY ("segment_id") REFERENCES "segments"."segment"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "segments"."segment_effort" ADD CONSTRAINT "segment_effort_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "social"."follow" ADD CONSTRAINT "follow_follower_id_user_id_fk" FOREIGN KEY ("follower_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "social"."follow" ADD CONSTRAINT "follow_followee_id_user_id_fk" FOREIGN KEY ("followee_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "subscriptions"."revenuecat_event" ADD CONSTRAINT "revenuecat_event_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "subscriptions"."user_subscription" ADD CONSTRAINT "user_subscription_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "users"."user_profile" ADD CONSTRAINT "user_profile_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "activity_user_started_at_idx" ON "activities"."activity" USING btree ("user_id","started_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "activity_processing_status_idx" ON "activities"."activity" USING btree ("processing_status") WHERE "activities"."activity"."processing_status" != 'processed';--> statement-breakpoint
CREATE INDEX "activity_track_route_gist_idx" ON "activities"."activity_track" USING gist ("route");--> statement-breakpoint
CREATE INDEX "activity_track_start_point_gist_idx" ON "activities"."activity_track" USING gist ("start_point");--> statement-breakpoint
CREATE INDEX "comment_activity_created_at_idx" ON "engagement"."comment" USING btree ("activity_id","created_at") WHERE "engagement"."comment"."deleted_at" is null;--> statement-breakpoint
CREATE INDEX "segment_path_gist_idx" ON "segments"."segment" USING gist ("path");--> statement-breakpoint
CREATE INDEX "segment_start_point_gist_idx" ON "segments"."segment" USING gist ("start_point");--> statement-breakpoint
CREATE INDEX "segment_effort_segment_elapsed_time_idx" ON "segments"."segment_effort" USING btree ("segment_id","elapsed_time_s");--> statement-breakpoint
CREATE INDEX "follow_followee_status_idx" ON "social"."follow" USING btree ("followee_id","status");