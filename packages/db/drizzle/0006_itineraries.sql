CREATE SCHEMA "itineraries";
--> statement-breakpoint
CREATE TYPE "itineraries"."elevation_source" AS ENUM('ign', 'mixed', 'open_meteo');--> statement-breakpoint
CREATE TYPE "itineraries"."leg_mode" AS ENUM('follow', 'straight');--> statement-breakpoint
CREATE TABLE "itineraries"."itinerary" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"sport_type_code" text NOT NULL,
	"name" text NOT NULL,
	"distance_m" real NOT NULL,
	"elevation_gain_m" real NOT NULL,
	"elevation_source" "itineraries"."elevation_source" NOT NULL,
	"track" geometry(LineStringZ,4326) NOT NULL,
	"map_polyline" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "itineraries"."itinerary_leg" (
	"itinerary_id" uuid NOT NULL,
	"position" integer NOT NULL,
	"mode" "itineraries"."leg_mode" NOT NULL,
	"path" geometry(LineString,4326) NOT NULL,
	CONSTRAINT "itinerary_leg_itinerary_id_position_pk" PRIMARY KEY("itinerary_id","position")
);
--> statement-breakpoint
CREATE TABLE "itineraries"."itinerary_waypoint" (
	"itinerary_id" uuid NOT NULL,
	"position" integer NOT NULL,
	"location" geometry(Point,4326) NOT NULL,
	CONSTRAINT "itinerary_waypoint_itinerary_id_position_pk" PRIMARY KEY("itinerary_id","position")
);
--> statement-breakpoint
ALTER TABLE "itineraries"."itinerary" ADD CONSTRAINT "itinerary_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "itineraries"."itinerary" ADD CONSTRAINT "itinerary_sport_type_code_sport_type_code_fk" FOREIGN KEY ("sport_type_code") REFERENCES "sports"."sport_type"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "itineraries"."itinerary_leg" ADD CONSTRAINT "itinerary_leg_itinerary_id_itinerary_id_fk" FOREIGN KEY ("itinerary_id") REFERENCES "itineraries"."itinerary"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "itineraries"."itinerary_waypoint" ADD CONSTRAINT "itinerary_waypoint_itinerary_id_itinerary_id_fk" FOREIGN KEY ("itinerary_id") REFERENCES "itineraries"."itinerary"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "itinerary_user_updated_at_idx" ON "itineraries"."itinerary" USING btree ("user_id","updated_at" DESC NULLS LAST,"id");