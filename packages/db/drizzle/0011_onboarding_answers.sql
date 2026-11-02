CREATE TYPE "users"."athlete_level" AS ENUM('beginner', 'intermediate', 'advanced', 'professional');--> statement-breakpoint
CREATE TYPE "users"."gender" AS ENUM('male', 'female', 'non_binary', 'undisclosed');--> statement-breakpoint
CREATE TYPE "users"."goal" AS ENUM('compete', 'discover_routes', 'health', 'meet_athletes', 'train_for_event', 'build_habit');--> statement-breakpoint
CREATE TABLE "users"."user_sport" (
	"user_id" uuid NOT NULL,
	"sport_code" text NOT NULL,
	"position" integer NOT NULL,
	CONSTRAINT "user_sport_user_id_sport_code_pk" PRIMARY KEY("user_id","sport_code")
);
--> statement-breakpoint
ALTER TABLE "users"."user_profile" ALTER COLUMN "gender" SET DATA TYPE "users"."gender" USING "gender"::"users"."gender";--> statement-breakpoint
ALTER TABLE "users"."user_profile" ADD COLUMN "level" "users"."athlete_level";--> statement-breakpoint
ALTER TABLE "users"."user_profile" ADD COLUMN "goals" "users"."goal"[];--> statement-breakpoint
ALTER TABLE "users"."user_sport" ADD CONSTRAINT "user_sport_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "users"."user_sport" ADD CONSTRAINT "user_sport_sport_code_sport_type_code_fk" FOREIGN KEY ("sport_code") REFERENCES "sports"."sport_type"("code") ON DELETE no action ON UPDATE no action;