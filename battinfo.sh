#!/bin/sh
# Pretty battery/charger status for qcom-msm8953 with correct units and thresholds.

# --- pick battery + charger sysfs paths ---
if [ -z "${BAT:-}" ]; then
  BAT=""
  for p in /sys/class/power_supply/*; do
    if [ "$(cat "$p/type" 2>/dev/null)" = "Battery" ]; then
      BAT="$p"
      break
    fi
  done
fi

find_ch() {
  for p in /sys/class/power_supply/*; do
    if [ -e "$p/input_current_limit" ] || [ -e "$p/current_max" ]; then
      echo "$p"
      return
    fi
  done
}
CH="${CH:-$(find_ch)}"

readf(){ cat "$1" 2>/dev/null || printf "?"; }

# --- raw values (µV/µA/µAh; temp in 0.1°C) ---
cap=$(readf "$BAT/capacity")
stat=$(readf "$BAT/status")
volt_uV=$(readf "$BAT/voltage_now")
curr_uA=$(readf "$BAT/current_now")
temp_dC=$(readf "$BAT/temp")

cfull_uAh=$(readf "$BAT/charge_full_design")
vmax_uV=$(readf "$BAT/voltage_max_design")
vmin_uV=$(readf "$BAT/voltage_min_design")
b_cccmax_uA=$(readf "$BAT/constant_charge_current_max")   # may be "?"

if [ -e "$CH/input_current_limit" ]; then
  ICL_NODE="$CH/input_current_limit"
elif [ -e "$CH/current_max" ]; then
  ICL_NODE="$CH/current_max"
else
  ICL_NODE=""
fi
icl_uA=$(readf "$ICL_NODE")
ccc_uA=$(readf "$CH/constant_charge_current")
cccmax_uA=$(readf "$CH/constant_charge_current_max")
term_uA=$(readf "$CH/charge_term_current")
ctype=$(readf "$CH/charge_type")
online=$(readf "$CH/online")

# --- converters (use BEGIN so awk never waits on stdin) ---
toV(){ awk -v n="$1" 'BEGIN{if(n~/^-?[0-9]+$/)printf"%.3f",n/1e6;else print "?"}'; }
to_mA(){ awk -v n="$1" 'BEGIN{if(n~/^-?[0-9]+$/)printf"%d",n/1000;else print "?"}'; }
to_mAh(){ awk -v n="$1" 'BEGIN{if(n~/^[0-9]+$/)printf"%d",n/1000;else print "?"}'; }
to_C(){ awk -v n="$1" 'BEGIN{if(n~/^-?[0-9]+$/)printf"%.1f",n/10;else print "?"}'; }
pwrW(){ awk -v uV="$1" -v uA="$2" 'BEGIN{
  if(uV~/^-?[0-9]+$/ && uA~/^-?[0-9]+$/){printf"%.3f",(uV/1e6)*((uA<0?-uA:uA)/1e6)}
  else print "?"
}'; }

volt_V=$(toV "$volt_uV")
ibat_mA=$(to_mA "$curr_uA")
temp_C=$(to_C "$temp_dC")
cfull_mAh=$(to_mAh "$cfull_uAh")
vmax_V=$(toV "$vmax_uV")
vmin_V=$(toV "$vmin_uV")
icl_mA=$(to_mA "$icl_uA")
ccc_mA=$(to_mA "$ccc_uA")
cccmax_mA=$(to_mA "${cccmax_uA:-$b_cccmax_uA}")
term_mA=$(to_mA "$term_uA")
pwr_W=$(pwrW "$volt_uV" "$curr_uA")

# --- direction note (this device: negative = charging) ---
dir="idle"
case "$curr_uA" in
  -*) dir="charging" ;;
  *[0-9]*) if [ "$curr_uA" -ge 20000 ] 2>/dev/null; then dir="discharging"; fi ;;
esac

# --- read guard thresholds from systemd unit(s) ---
get_env(){
  var="$1"
  for f in \
    /etc/systemd/system/charge-icl-guard.service.d/override.conf \
    /etc/systemd/system/charge-icl-guard.service
  do
    [ -r "$f" ] || continue
    # Expect lines like: Environment=VAR=VALUE (optionally quoted)
    val=$(awk -v v="$var" -F= '
      $1 ~ /^Environment$/ && $2==v {
        # Value starts at $3; strip leading/trailing quotes if present
        gsub(/^"/,"",$3); gsub(/"$/,"",$3); print $3
      }' "$f" | tail -n1)
    [ -n "$val" ] || val=$(grep -E "^Environment=${var}=" "$f" | tail -n1 | sed -E "s/^Environment=${var}=//")
    # strip quotes once more just in case
    val="${val%\"}"; val="${val#\"}"
    if [ -n "$val" ]; then echo "$val"; return; fi
  done
  echo "?"
}

STOP="$(get_env STOP_THRESHOLD)"
START="$(get_env START_THRESHOLD)"
ICL_LOW="$(get_env ICL_LOW)"

# --- mode heuristic from ICL ---
mode="normal"
case "$icl_uA" in
  ''|'?'|*[!0-9]*) ;;
  *)
    case "$ICL_LOW" in
      ''|'?'|*[!0-9]*) ;;
      *) [ "$icl_uA" -le "$ICL_LOW" ] 2>/dev/null && mode="limited" ;;
    esac
    ;;
esac

bn=$(basename "$BAT"); cn=$(basename "$CH")

echo "=== Battery: $bn ==="
printf " State:           %s (%s%%)\n" "${stat:-?}" "${cap:-?}"
printf " Voltage:         %s V (design max %s V, min %s V)\n" "$volt_V" "$vmax_V" "$vmin_V"
if [ "$pwr_W" != "?" ]; then
  note="← load (discharging)"; [ "${curr_uA#-}" != "$curr_uA" ] && note="→ batt (charging)"
  case "$stat" in
    Charging|Full) note="batt (charging)" ;;
    Discharging) note="load (discharging)" ;;
  esac
  printf " Current:         %s mA   Power: %s W  %s\n" "$ibat_mA" "$pwr_W" "$note"
else
  printf " Current:         %s mA   Power: ? W\n" "$ibat_mA"
fi
printf " Temperature:     %s °C\n" "$temp_C"
printf " Design capacity: %s mAh\n" "$cfull_mAh"

echo
echo "=== Charger: $cn ==="
printf " Online:          %s   Type: %s\n" "$( [ "$online" = "1" ] && echo yes || echo no )" "${ctype:-?}"
printf " ICL (now):       %s mA   Mode: %s\n" "$icl_mA" "$mode"
printf " CCC (now):       %s mA\n" "$ccc_mA"
printf " CCC (max):       %s mA\n" "$cccmax_mA"
printf " Term current:    %s mA\n" "$term_mA"

echo
echo "=== Guard thresholds ==="
printf " STOP at:         %s %%   (set LOW/trickle)\n" "$STOP"
printf " START at:        %s %%   (restore HIGH)\n" "$START"
printf " ICL_LOW:         %s mA\n" "$(to_mA "$ICL_LOW")"
