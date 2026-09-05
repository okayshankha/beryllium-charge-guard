#!/bin/sh
# icl-menu.sh — simple number menu to adjust USB input current limit (ICL)
# Reuses /usr/local/bin/battinfo.sh for status output (no duplicated logic).

set -eu

BATTINFO="${BATTINFO:-/usr/local/bin/battinfo}"

# Find charger node with a supported input-current limit property.
find_ch() {
  for p in /sys/class/power_supply/*; do
    if [ -e "$p/input_current_limit" ] || [ -e "$p/current_max" ]; then
      echo "$p"
      return
    fi
  done
  return 1
}

CH="${CH:-$(find_ch || true)}"
[ -n "${CH:-}" ] && [ -d "$CH" ] || { echo "Charger sysfs not found (no supported current-limit node)."; exit 1; }

if [ -e "$CH/input_current_limit" ]; then
  ICL_NODE="$CH/input_current_limit"
elif [ -e "$CH/current_max" ]; then
  ICL_NODE="$CH/current_max"
else
  echo "No supported current-limit node under $CH."
  exit 1
fi

need_sudo() { [ -w "$ICL_NODE" ] && return 1 || return 0; }

set_icl_ma() {
  mA="$1"
  case "$mA" in ''|*[!0-9]* ) echo "Invalid mA: $mA"; return 1 ;; esac
  [ "$mA" -gt 0 ] || { echo "Current must be greater than zero."; return 1; }
  [ $((mA % 25)) -eq 0 ] || { echo "Current must be a multiple of 25 mA."; return 1; }
  [ "$mA" -le 4800 ] || { echo "Current must not exceed 4800 mA."; return 1; }
  new_uA=$(( mA * 1000 ))

  # write ICL
  if [ -w "$ICL_NODE" ]; then
    if ! printf "%s\n" "$new_uA" > "$ICL_NODE"; then
      echo "Failed to write $ICL_NODE."
      return 1
    fi
  elif command -v sudo >/dev/null 2>&1; then
    if ! printf "%s\n" "$new_uA" | sudo tee "$ICL_NODE" >/dev/null; then
      echo "No permission to write $ICL_NODE (run with sudo)."
      return 1
    fi
  else
    echo "No permission to write $ICL_NODE (run with sudo)."
    return 1
  fi
  actual=$(cat "$ICL_NODE" 2>/dev/null || echo "")
  [ "$actual" = "$new_uA" ] || { echo "ICL readback mismatch: requested $new_uA, got ${actual:-?}"; return 1; }
  echo "ICL set to ${mA} mA"
}

guard_status() {
  command -v systemctl >/dev/null 2>&1 || { echo "unknown"; return; }
  systemctl is-active --quiet charge-icl-guard.timer && echo "active" || echo "inactive"
}
guard_pause()  { command -v systemctl >/dev/null 2>&1 && sudo systemctl stop  charge-icl-guard.timer >/dev/null 2>&1 || true; }
guard_resume() { command -v systemctl >/dev/null 2>&1 && sudo systemctl start charge-icl-guard.timer >/dev/null 2>&1 || true; }

show_status() {
  echo
  if [ -x "$BATTINFO" ]; then
    "$BATTINFO"
  else
    echo "Note: $BATTINFO not found/executable; install your battinfo for full status."
  fi
  echo
  echo "Guard timer: $(guard_status)"
  echo "ICL node: $ICL_NODE"
  echo
}

# Menu loop
while :; do
  show_status
  cat <<EOF
Choose an option:
  1) Set ICL = 100 mA   (trickle)
  2) Set ICL = 500 mA   (typical USB2)
  3) Set ICL = 900 mA   (high)
  4) Set ICL = 1500 mA  (very high, if PSU/cable allow)
  5) Set ICL = custom mA
  6) Pause guard timer
  7) Resume guard timer
  8) Refresh
  0) Exit
EOF
  printf "Select: "
  IFS= read -r choice || exit 0
  case "$choice" in
    1) set_icl_ma 100 ;;
    2) set_icl_ma 500 ;;
    3) set_icl_ma 900 ;;
    4) set_icl_ma 1500 ;;
    5) printf "Enter mA (integer): "; IFS= read -r mA && set_icl_ma "$mA" ;;
    6) guard_pause;  echo "Guard timer paused." ;;
    7) guard_resume; echo "Guard timer resumed." ;;
    8) : ;;
    0) echo "Bye."; exit 0 ;;
    *) echo "Unknown option." ;;
  esac
done

