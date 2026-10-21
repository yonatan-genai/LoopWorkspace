#!/bin/bash
# Fork addition. Emails a Loop certificate renewal failure from alerts@horan.casa.
# usage: loop_cert_alert.sh "<subject>" "<what failed>"
# env: RESEND_API_KEY, ALERT_TO, RUN_URL, ALERT_HMAC_KEY, ALERT_SEVERITY (default error); STATE_FILE (from fastlane loop_cert_state) is optional.
set -u
SUBJECT="$1"
WHAT="$2"
STATE_FILE="${STATE_FILE:-fastlane/loop_cert_state.txt}"
if [ -s "$STATE_FILE" ]; then
  STATE=$(cat "$STATE_FILE")
else
  STATE="State unknown: the state check did not run or failed. Open the run log."
fi
TEXT="What failed: $WHAT

State now:
$STATE"

# Send through the horan-casa alert worker (Yossi session + its own alerts@ mail).
# Resend below is only the fallback when the worker is unset, down or not ok.
if [ -n "${ALERT_HMAC_KEY:-}" ]; then
  body=$(jq -nc --arg t "$SUBJECT" --arg b "${TEXT:0:1900}" --arg s "${ALERT_SEVERITY:-error}" --arg u "$RUN_URL" \
    '{source:"loop-cert",severity:$s,title:$t[0:200],body:$b,url:$u}')
  t=$(date +%s)
  sig=$(printf '%s.%s' "$t" "$body" | openssl dgst -sha256 -hmac "$ALERT_HMAC_KEY" -r | cut -d' ' -f1)
  resp=$(curl -sS --max-time 20 -X POST https://horan-casa-mail.8kicks.workers.dev/alert \
    -H "X-Horan-Signature: t=$t,v1=$sig" -H 'Content-Type: application/json' --data-raw "$body" || true)
  echo "alert worker: $resp"
  if printf '%s' "$resp" | jq -e '.ok == true' >/dev/null 2>&1; then
    echo "alert sent via worker: $SUBJECT" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
    exit 0
  fi
  echo "::warning::alert worker did not return ok, falling back to Resend"
else
  echo "::warning::ALERT_HMAC_KEY is not set, skipped the alert worker"
fi

if [ -z "${RESEND_API_KEY:-}" ] || [ -z "${ALERT_TO:-}" ]; then
  echo "::error::$SUBJECT. RESEND_API_KEY or CERT_ALERT_EMAIL is not set, so no email was sent."
  exit 1
fi
jq -n --arg to "$ALERT_TO" --arg subject "$SUBJECT" --arg text "$TEXT" --arg url "$RUN_URL" '{
  from: "Horan Alerts <alerts@horan.casa>", to: [$to], subject: $subject,
  text: ($text + "\n\nRun: " + $url)
}' | curl -sS --fail-with-body -X POST https://api.resend.com/emails \
  -H "Authorization: Bearer $RESEND_API_KEY" -H "Content-Type: application/json" -d @-
echo
echo "alert sent via Resend fallback: $SUBJECT" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
