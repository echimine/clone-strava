CREATE TYPE "public"."session_auth_method" AS ENUM('password_2fa', 'password', 'email_otp', 'google');--> statement-breakpoint
ALTER TABLE "session" ADD COLUMN "auth_method" "session_auth_method";