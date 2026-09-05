#!/bin/sh
# Monitor whether USB input is charging the battery or only powering the phone.

BATT=${BATT:-/sys/class/power_supply/qcom-battery}
CHARGER=${CHARGER:-/sys/class/power_supply/pmi8998-charger}
SAMPLES=${SAMPLES:-6}
INTERVAL=${INTERVAL:-30}

readf() {
  cat "$1" 2>/dev/null || printf '?'
}

to_mA() {
  awk -v value="$1" \
    'BEGIN { if (value ~ /^-?[0-9]+$/) printf "%dmA", value / 1000; else printf "?" }'
}

printf 'Monitoring battery and charger for %s samples every %s seconds\n' \
  "$SAMPLES" "$INTERVAL"
printf 'battery=%s charger=%s\n\n' "$BATT" "$CHARGER"

printf '%-8s %-13s %-8s %-16s %-16s %-7s\n' \
  time status capacity battery_current charger_current online

i=1
while [ "$i" -le "$SAMPLES" ]; do
  printf '%-8s %-13s %-8s %-16s %-16s %-7s\n' \
    "$(date '+%H:%M:%S')" \
    "$(readf "$BATT/status")" \
    "$(readf "$BATT/capacity")" \
    "$(to_mA "$(readf "$BATT/current_now")")" \
    "$(to_mA "$(readf "$CHARGER/current_now")")" \
    "$(readf "$CHARGER/online")"
  [ "$i" -lt "$SAMPLES" ] && sleep "$INTERVAL"
  i=$((i + 1))
done
