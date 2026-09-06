#!/bin/sh
# Install ICL-based charger guard + battinfo from the current repo directory.
# Usage:
#   ./install.sh            # install/enable
#   ./install.sh --uninstall
#   ./install.sh --src /path/to/dir   # (optional) use a different source dir

set -eu

# --- re-exec as root via doas/sudo if needed ---
if [ "$(id -u)" -ne 0 ]; then
  if command -v doas >/dev/null 2>&1; then
    exec doas -- "$0" "$@"
  elif command -v sudo >/dev/null 2>&1; then
    exec sudo -- "$0" "$@"
  else
    echo "This script needs root. Install doas/sudo or run as root." >&2
    exit 1
  fi
fi

# --- defaults ---
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
SRC="$SCRIPT_DIR"
UNINSTALL=0

# --- args ---
while [ $# -gt 0 ]; do
  case "$1" in
    --src)
      [ $# -ge 2 ] || { echo "Missing value for --src" >&2; exit 1; }
      SRC="$2"; shift 2 ;;
    --uninstall)
      UNINSTALL=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--src DIR] [--uninstall]"
      exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1 ;;
  esac
done

# --- helpers ---
require_files() {
  for f in charge_icl_guard.sh battinfo.sh icl-menu.sh charge-icl-guard.service charge-icl-guard.timer override.conf; do
    if [ ! -r "$SRC/$f" ]; then
      echo "Missing: $SRC/$f" >&2
      exit 1
    fi
  done
}

install_files() {
  echo "Installing from: $SRC"

  # Scripts (install without .sh extensions)
  mkdir -p /usr/local/bin
  install -m 0755 "$SRC/charge_icl_guard.sh" /usr/local/bin/charge-icl-guard
  install -m 0755 "$SRC/battinfo.sh"         /usr/local/bin/battinfo
  install -m 0755 "$SRC/icl-menu.sh"         /usr/local/bin/icl-menu

  # Units
  mkdir -p /etc/systemd/system
  install -m 0644 "$SRC/charge-icl-guard.service" /etc/systemd/system/charge-icl-guard.service
  install -m 0644 "$SRC/charge-icl-guard.timer"   /etc/systemd/system/charge-icl-guard.timer
  mkdir -p /etc/systemd/system/charge-icl-guard.service.d
  install -m 0644 "$SRC/override.conf"            /etc/systemd/system/charge-icl-guard.service.d/override.conf

  # Never install runtime state from the repo
  if [ -f "$SRC/charge-icl.high" ]; then
    echo "Note: ignoring $SRC/charge-icl.high (runtime state; recreated at boot)."
  fi

  systemctl daemon-reload
  systemctl enable --now charge-icl-guard.timer

  # Apply the policy once immediately so a fresh install/reinstall is active
  # right away instead of waiting for the next timer tick.
  echo "Running an immediate guard pass..."
  if ! systemctl start charge-icl-guard.service; then
    echo "Warning: initial guard run failed; timer remains installed." >&2
  fi

  echo
  echo "Installed. Quick check:"
  /usr/local/bin/battinfo || true
  echo
  systemctl list-timers charge-icl-guard.timer --no-pager || true
}

restore_saved_icl() {
  STATE=/run/charge-icl.high
  [ -r "$STATE" ] || return 0

  high=$(cat "$STATE" 2>/dev/null || true)
  case "$high" in
    ''|*[!0-9]*)
      echo "Warning: ignoring invalid saved ICL value: $high" >&2
      return 0
      ;;
  esac
  if [ "$high" -le 0 ] || [ $((high % 25000)) -ne 0 ]; then
    echo "Warning: ignoring invalid saved ICL value: $high uA." >&2
    return 0
  fi

  # Restore the charger limit before removing the guard. This prevents the
  # last LOW value from remaining active after uninstall.
  for node in /sys/class/power_supply/*/input_current_limit \
              /sys/class/power_supply/*/current_max; do
    [ -e "$node" ] || continue
    charger_dir=${node%/*}
    if [ -e "$charger_dir/online" ] &&
       [ "$(cat "$charger_dir/online" 2>/dev/null || true)" != "1" ]; then
      continue
    fi
    if [ -w "$node" ]; then
      printf "%s\n" "$high" > "$node" 2>/dev/null || continue
      if [ "$(cat "$node" 2>/dev/null || true)" = "$high" ]; then
        echo "Restored charger input current to ${high} uA."
        rm -f "$STATE"
        return 0
      fi
    fi
  done

  echo "Warning: could not restore saved charger input current (${high} uA)." >&2
}

uninstall_files() {
  echo "Disabling services..."
  systemctl disable --now charge-icl-guard.timer 2>/dev/null || true
  systemctl disable --now charge-icl-guard.service 2>/dev/null || true

  restore_saved_icl

  echo "Removing files..."
  rm -f /usr/local/bin/charge-icl-guard \
        /usr/local/bin/battinfo \
        /usr/local/bin/icl-menu \
        /etc/systemd/system/charge-icl-guard.timer \
        /etc/systemd/system/charge-icl-guard.service
  rm -f /etc/systemd/system/charge-icl-guard.service.d/override.conf
  rmdir  /etc/systemd/system/charge-icl-guard.service.d 2>/dev/null || true

  systemctl daemon-reload
  echo "Uninstalled."
}

# --- main ---
if [ "$UNINSTALL" -eq 1 ]; then
  uninstall_files
else
  require_files
  install_files
fi
