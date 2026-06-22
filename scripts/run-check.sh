#!/bin/sh
# ──────────────────────────────────────────────────────────────────────────────
# run-check.sh
#
# Called by Ofelia on each schedule tick.  Runs urlwatch for the given tier,
# captures its stdout (which only contains output when something has changed,
# because `display.unchanged: false` is set in urlwatch.yaml), and forwards
# any report to Apprise.
#
# Usage:  run-check.sh <tier>
#   tier: fast | hourly | daily
#
# Required environment variable:
#   APPRISE_URLS  Space-separated list of Apprise notification URLs.
#                 If empty, changed content is printed to stdout instead.
#
# Exit codes:
#   0  Success (check ran; notification sent or nothing changed)
#   1  Configuration error (missing tier argument or missing URLs file)
# ──────────────────────────────────────────────────────────────────────────────

TIER="${1}"

if [ -z "$TIER" ]; then
  echo "[run-check] ERROR: tier argument required (fast|hourly|daily)" >&2
  exit 1
fi

CONFIG_DIR="/config"
CACHE_DIR="/cache"

URLS_FILE="${CONFIG_DIR}/urls-${TIER}.yaml"
CACHE_FILE="${CACHE_DIR}/cache-${TIER}.db"
MAIN_CONFIG="${CONFIG_DIR}/urlwatch.yaml"

if [ ! -f "$URLS_FILE" ]; then
  echo "[run-check] No URL file for tier '${TIER}' at ${URLS_FILE} – skipping." >&2
  exit 0
fi

# ── Run urlwatch ──────────────────────────────────────────────────────────────
# urlwatch exits 0 when all checks complete (changed or not).
# Errors (network, parse) are included in stdout because we merged stderr above.
# We capture both streams so failures also trigger a notification.
OUTPUT=$(urlwatch \
  --urls  "$URLS_FILE" \
  --cache "$CACHE_FILE" \
  --config "$MAIN_CONFIG" \
  2>&1) || true

# No output means nothing changed and no errors – nothing to do.
if [ -z "$OUTPUT" ]; then
  exit 0
fi

# ── Dispatch to Apprise ───────────────────────────────────────────────────────
if [ -z "$APPRISE_URLS" ]; then
  echo "[run-check] APPRISE_URLS not configured – printing report to stdout:" >&2
  printf '%s\n' "$OUTPUT"
  exit 0
fi

# Word-splitting on $APPRISE_URLS is intentional here: each space-delimited
# token is a separate Apprise URL passed as its own positional argument.
# shellcheck disable=SC2086
apprise \
  --title "Web change detected [${TIER}]" \
  --body  "$OUTPUT" \
  $APPRISE_URLS
