#!/bin/bash
# Fork addition. Emails a Loop certificate renewal failure from alerts@horan.casa.
# usage: loop_cert_alert.sh "<subject>" "<what failed>"
# env: RESEND_API_KEY, ALERT_TO, RUN_URL; STATE_FILE (from fastlane loop_cert_state) is optional.
set -u
SUBJECT="$1"
WHAT="$2"
STATE_FILE="${STATE_FILE:-fastlane/loop_cert_state.txt}"
if [ -s "$STATE_FILE" ]; then
  STATE=$(cat "$STATE_FILE")
else
  STATE="State unknown: the state check did not run or failed. Open the run log."
fi
if [ -z "${RESEND_API_KEY:-}" ] || [ -z "${ALERT_TO:-}" ]; then
  echo "::error::$SUBJECT. RESEND_API_KEY or CERT_ALERT_EMAIL is not set, so no email was sent."
  exit 1
fi
jq -n --arg to "$ALERT_TO" --arg subject "$SUBJECT" --arg what "$WHAT" --arg state "$STATE" --arg url "$RUN_URL" '{
  from: "Horan Alerts <alerts@horan.casa>", to: [$to], subject: $subject,
  text: ("What failed: " + $what + "\n\nState now:\n" + $state + "\n\nRun: " + $url)
}' | curl -sS --fail-with-body -X POST https://api.resend.com/emails \
  -H "Authorization: Bearer $RESEND_API_KEY" -H "Content-Type: application/json" -d @-
echo
echo "alert sent: $SUBJECT" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
