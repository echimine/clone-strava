#!/usr/bin/env bash
# Creates the local test user (email/password, Better Auth) on the dev API.
# Dev only: refuses any host other than localhost. Idempotent: an existing user is reported, not an error.
set -euo pipefail

API_URL="${API_URL:-http://localhost:3001}"
case "$API_URL" in
  http://localhost:*|http://127.0.0.1:*) ;;
  *) echo "Refusing to create a test user on $API_URL (dev only)." >&2; exit 1 ;;
esac

TEST_USER_NAME="Test Map"
TEST_USER_EMAIL="test.map@stravaclone.test"
TEST_USER_PASSWORD="MapTest-Local-2026!"

status=$(curl -s -o /tmp/create-test-user.json -w "%{http_code}" \
  -X POST "$API_URL/api/auth/sign-up/email" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$TEST_USER_NAME\",\"email\":\"$TEST_USER_EMAIL\",\"password\":\"$TEST_USER_PASSWORD\"}")

case "$status" in
  200) echo "Created $TEST_USER_EMAIL" ;;
  422) echo "$TEST_USER_EMAIL already exists" ;;
  *) echo "Sign-up failed ($status):" >&2; cat /tmp/create-test-user.json >&2; echo >&2; exit 1 ;;
esac
