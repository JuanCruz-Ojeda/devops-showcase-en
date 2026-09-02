#!/usr/bin/env bash
#
# Smoke test for the mini-app. Checks that the running stack responds correctly:
#   - GET /            -> 200
#   - GET /health      -> 200
#   - GET /cache-test  -> 200 and the Redis counter increments between calls
#
# Usage:
#   ./scripts/smoke-test.sh [BASE_URL]
#
# Default BASE_URL: http://localhost:8080
# Used both in CI and in the local demo.

set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
TIMEOUT_SECONDS="${SMOKE_TIMEOUT:-60}"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

# Returns the HTTP status code of a GET to the given path.
http_code() {
  curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}$1"
}

# Waits until /health responds 200 (the app may take a while to start).
wait_for_app() {
  echo "Waiting for the app to respond at ${BASE_URL}/health (up to ${TIMEOUT_SECONDS}s)..."
  local deadline=$(( SECONDS + TIMEOUT_SECONDS ))
  while (( SECONDS < deadline )); do
    if [ "$(http_code /health)" = "200" ]; then
      green "The app is up."
      return 0
    fi
    sleep 2
  done
  red "Timeout: the app did not return 200 at ${BASE_URL}/health"
  return 1
}

# Checks that a route returns 200.
check_200() {
  local route="$1"
  local code
  code="$(http_code "$route")"
  if [ "$code" = "200" ]; then
    green "OK   GET ${route} -> 200"
  else
    red   "FAIL GET ${route} -> ${code} (expected 200)"
    return 1
  fi
}

# Checks that the Redis counter increments between two calls to /cache-test.
check_redis_increments() {
  local r1 r2 h1 h2
  r1="$(curl -fsS "${BASE_URL}/cache-test")"
  r2="$(curl -fsS "${BASE_URL}/cache-test")"
  # The response is JSON like {"hits":"5","redis_host":"redis"}
  h1="$(printf '%s' "$r1" | grep -o '"hits":"[0-9]*"' | grep -o '[0-9]*')"
  h2="$(printf '%s' "$r2" | grep -o '"hits":"[0-9]*"' | grep -o '[0-9]*')"
  if [ -n "$h1" ] && [ -n "$h2" ] && [ "$h2" -gt "$h1" ]; then
    green "OK   /cache-test: the Redis counter incremented (${h1} -> ${h2})"
  else
    red   "FAIL /cache-test: the counter did not increment (${h1:-?} -> ${h2:-?})"
    red   "      response 1: ${r1}"
    red   "      response 2: ${r2}"
    return 1
  fi
}

main() {
  wait_for_app
  check_200 /
  check_200 /health
  check_200 /cache-test
  check_redis_increments
  echo
  green "Smoke test OK"
}

main "$@"
