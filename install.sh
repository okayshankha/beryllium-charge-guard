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

uninstall_files() {
  echo "Disabling services..."
  systemctl disable --now charge-icl-guard.timer 2>/dev/null || true
  systemctl disable --now charge-icl-guard.service 2>/dev/null || true

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
