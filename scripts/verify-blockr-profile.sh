#!/usr/bin/env bash
# Inspect only Blockr's regenerated CI profiles. Never print a decoded profile.
set -euo pipefail
profile=${1:?profile path required}
identifier=${2:?Blockr bundle identifier required}
case "$identifier" in
  com.calumwebb.blockr|com.calumwebb.blockr.ShieldConfiguration|com.calumwebb.blockr.ShieldAction|com.calumwebb.blockr.DeviceActivityMonitor) ;;
  *) echo 'Only Blockr profiles may be inspected by this check' >&2; exit 64 ;;
esac
umask 077
decoded=$(mktemp "${TMPDIR:-/tmp}/blockr-profile.XXXXXX")
trap 'rm -f "$decoded"' EXIT
security cms -D -i "$profile" > "$decoded"
family=$(/usr/libexec/PlistBuddy -c 'Print Entitlements:com.apple.developer.family-controls' "$decoded")
app_id=$(/usr/libexec/PlistBuddy -c 'Print Entitlements:application-identifier' "$decoded")
[[ "$family" == true && "$app_id" == "X9E4HG27NK.$identifier" ]] || {
  echo "::error::Regenerated App Store profile for $identifier lacks Family Controls (Distribution) or has the wrong App ID" >&2
  exit 1
}
echo "Verified Family Controls in $identifier App Store profile"
