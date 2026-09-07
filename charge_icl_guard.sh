#!/bin/sh
# Throttle USB input current (µA) to keep SoC in a band.
# Supports both input_current_limit and qcom_smbx's current_max.

# Thresholds (overridable via systemd Environment=…)
STOP=${STOP_THRESHOLD:-80}        # %: go to LOW when >= STOP
START=${START_THRESHOLD:-40}      # %: go to HIGH when <= START
ICL_LOW=${ICL_LOW:-100000}        # µA: 100 mA

readf(){ cat "$1" 2>/dev/null || printf "?"; }
log(){ command -v logger >/dev/null 2>&1 && logger -t charge-icl "$@" || true; }

# Sysfs (with autodetect fallbacks)
BAT=/sys/class/power_supply/qcom-battery
CH=/sys/class/power_supply/qcom-smbchg-usb
if [ ! -d "$BAT" ]; then
  for p in /sys/class/power_supply/*; do
    if [ "$(cat "$p/type" 2>/dev/null)" = "Battery" ]; then
      BAT="$p"
      break
    fi
  done
fi
if [ ! -d "$CH" ]; then
  for p in /sys/class/power_supply/*; do
    if [ -e "$p/input_current_limit" ] || [ -e "$p/current_max" ]; then
      CH="$p"
      break
    fi
  done
fi

# Validate required sysfs nodes exist
[ -d "$BAT" ] || { log "ERROR: Battery sysfs path not found"; exit 1; }
[ -d "$CH" ] || { log "ERROR: Charger sysfs path not found"; exit 1; }

if [ -e "$CH/input_current_limit" ]; then
  ICL_NODE="$CH/input_current_limit"
elif [ -e "$CH/current_max" ]; then
  ICL_NODE="$CH/current_max"
else
  log "ERROR: No supported current-limit node under $CH"
  exit 1
fi
STAT_NODE="$BAT/status"
CAP_NODE="$BAT/capacity"
ONLINE_NODE="$CH/online"
STATE=/run/charge-icl.high        # saved "high" value for this boot

case "$ICL_LOW" in
  ''|*[!0-9]*) log "ERROR: ICL_LOW must be an integer in microamps"; exit 1 ;;
esac
[ "$ICL_LOW" -gt 0 ] || { log "ERROR: ICL_LOW must be greater than zero"; exit 1; }
[ $((ICL_LOW % 25000)) -eq 0 ] || { log "ERROR: ICL_LOW must be a multiple of 25000 uA"; exit 1; }

# Validate configuration
if [ "$START" -ge "$STOP" ]; then
  log "ERROR: START_THRESHOLD ($START) must be less than STOP_THRESHOLD ($STOP)"
  exit 1
fi

# Read capacity (numeric) - validate it's readable and numeric
cap=$(readf "$CAP_NODE")
case "$cap" in ''|'?') log "WARNING: Cannot read battery capacity from $CAP_NODE"; exit 0;; esac
cap=$(printf "%s" "$cap" | tr -cd '0-9')
[ -z "$cap" ] && { log "ERROR: Battery capacity is not numeric"; exit 1; }

# Do not program the input limit while no USB input is present. qcom_smbx
# reports current_max=0 in that state, which is not a write/readback failure.
if [ -e "$ONLINE_NODE" ]; then
  online=$(readf "$ONLINE_NODE")
  [ "$online" = "1" ] || { log "charger offline; skipping ICL update"; exit 0; }
fi

# Current / "high" ICL - validate ICL node is readable
ICL_CUR=$(readf "$ICL_NODE")
[ "$ICL_CUR" = "?" ] && { log "ERROR: Cannot read ICL from $ICL_NODE"; exit 1; }
if [ -e "$STATE" ]; then
  ICL_HIGH=$(readf "$STATE")
else
  ICL_HIGH="$ICL_CUR"
fi

case "$ICL_HIGH" in
  ''|*[!0-9]*) log "ERROR: saved high ICL is invalid: $ICL_HIGH"; exit 1 ;;
esac
[ "$ICL_HIGH" -gt 0 ] || { log "ERROR: saved high ICL must be greater than zero"; exit 1; }
[ $((ICL_HIGH % 25000)) -eq 0 ] || {
  log "ERROR: saved high ICL must be a multiple of 25000 uA"
  exit 1
}

# Only save a device-reported positive value. A zero value can appear briefly
# before the charger negotiates input current and must never become HIGH.
if [ ! -e "$STATE" ]; then
  echo "$ICL_HIGH" > "$STATE" 2>/dev/null || log "WARNING: Cannot save ICL state to $STATE"
fi

# Decide target
want=""
[ "$cap" -ge "$STOP" ] && want=low
[ "$cap" -le "$START" ] && want=high
[ -z "$want" ] && exit 0

# Write helper
apply(){
  val="$1"
  [ -w "$ICL_NODE" ] || { log "ERROR: ICL node not writable: $ICL_NODE"; return 1; }
  case "$val" in ''|*[!0-9]*) log "ERROR: invalid ICL value: $val"; return 1 ;; esac
  [ "$val" -gt 0 ] || { log "ERROR: ICL must be greater than zero"; return 1; }
  [ $((val % 25000)) -eq 0 ] || { log "ERROR: ICL must be a multiple of 25000 uA"; return 1; }
  [ "$ICL_CUR" = "$val" ] && { log "ICL already $val, no change"; return 0; }
  # Qualcomm charger sysfs values can briefly report the previous negotiated
  # value while the charger applies a new limit. Retry the write/readback
  # before treating that transient state as a service failure.
  attempt=1
  got=""
  while [ "$attempt" -le 3 ]; do
    if printf "%s\n" "$val" > "$ICL_NODE" 2>/dev/null; then
      got=$(readf "$ICL_NODE")
      if [ "$got" = "$val" ]; then
        ICL_CUR="$got"
        log "set ICL=$got (requested $val) at cap=${cap}%"
        return 0
      fi
    else
      got="write failed"
    fi
    [ "$attempt" -lt 3 ] && sleep 1
    attempt=$((attempt + 1))
  done
  log "ERROR: ICL readback=$got (requested $val) after 3 attempts"
  return 1
}

case "$want" in
  low)
    # Set trickle/limited ICL; do not force a kick here (we're not aiming to ramp charge).
    apply "$ICL_LOW" || exit 1
    ;;
  high)
    apply "$ICL_HIGH" || exit 1
    ;;
esac

exit 0
