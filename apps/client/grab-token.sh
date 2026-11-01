#!/bin/sh
# Catches a fresh Battle.net launcher token for a headset login: start this, then click Play in
# Battle.net. When the Mac client starts it's killed straight away (before it spends the token), and
# once Battle.net has written the new token (ACCOUNT_TS changes; the client can start before that,
# and exporting then relays the old, spent token) the net.battle prefs are exported to $1. Keep that
# out of the repo (the scratchpad). Prints only sizes and timestamps. Then copy it to the headset:
#   xcrun devicectl device copy to --device <id> --domain-type appDataContainer
#     --domain-identifier $SP_BUNDLE_ID --source $1 --destination Library/spnetbattle.plist
# (the AppKit shim imports it into net.battle at startup and deletes it).
# --now (second argument) exports the current prefs without waiting, for a token that was written
# after an earlier export and never used. Prints the client's launch arguments, to pass to run.sh.
# Watches for the flavor in scripts/flavor.sh (the last one run.sh ran, unless SP_FLAVOR is set).
set -e
. "$(dirname "$0")/../../scripts/flavor.sh"
OUT=${1:?usage: grab-token.sh <out.plist> [--now]}
TS_KEY="Launch Options/WoW/ACCOUNT_TS"
rm -f "$OUT"
if [ "$2" = --now ]; then
  defaults export net.battle "$OUT"
  echo "ACCOUNT_TS $(defaults read net.battle "$TS_KEY"); exported $(wc -c < "$OUT") B"
  exit 0
fi
OLD=$(defaults read net.battle "$TS_KEY" 2>/dev/null || true)
echo "waiting for Play (current ACCOUNT_TS $OLD)"
while :; do
  P=$(pgrep -f "$SP_CLIENT" || true)
  [ -n "$P" ] && break
  sleep 0.05
done
ARGS=$(ps -o args= -p $P | sed "s|^$SP_CLIENT ||" || true)
kill -9 $P
echo "caught the client launch, arguments: $ARGS"
# Without -launcherlogin, Battle.net made no new token (its log: "SSO Token generation error:
# err=ERROR_API_NOT_READY"; restarting Battle.net fixes it), and exporting would relay the spent one.
case " $ARGS " in
  *" -launcherlogin "*) ;;
  *) echo "launched without -launcherlogin: Battle.net made no new token. Restart Battle.net and retry."; exit 1 ;;
esac
for i in $(seq 150); do
  NEW=$(defaults read net.battle "$TS_KEY" 2>/dev/null || true)
  [ -n "$NEW" ] && [ "$NEW" != "$OLD" ] && break
  sleep 0.1
done
if [ "$NEW" = "$OLD" ]; then
  echo "ACCOUNT_TS didn't change in 15 s: no new token, nothing exported"
  exit 1
fi
defaults export net.battle "$OUT"
echo "new ACCOUNT_TS $NEW; exported $(wc -c < "$OUT") B"
