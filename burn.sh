# save as: burn.sh
# usage:
#   ./burn.sh [-c CORES] [-t SECONDS] [-q] [--no-stress]
#   ./burn.sh [CORES] [SECONDS]
#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: burn.sh [-c CORES] [-t SECONDS] [-q] [--no-stress] [--]
       burn.sh [CORES] [SECONDS]

Burns CPU for the given duration. If stress-ng is available, it will be used
by default; add --no-stress to force the shell fallback.

Options:
  -c CORES      Number of worker processes (default: number of CPUs)
  -t SECONDS    Duration to run (default: 10)
  -q            Quiet (suppress info messages)
  --no-stress   Force fallback even if stress-ng is present
  -h, --help    Show this help

Examples:
  ./burn.sh 4 30
  ./burn.sh -c "$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)" -t 20
USAGE
}

# defaults
CORES="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
SECS="10"
QUIET=0
USE_STRESS="auto"  # auto | no

# parse flags/positionals
pos1=""; pos2=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -c) CORES="${2:?}"; shift 2 ;;
    -t) SECS="${2:?}"; shift 2 ;;
    -q) QUIET=1; shift ;;
    --no-stress) USE_STRESS="no"; shift ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *)  if [ -z "$pos1" ]; then pos1="$1"; else pos2="$1"; fi; shift ;;
  esac
done
[ -n "$pos1" ] && CORES="$pos1"
[ -n "$pos2" ] && SECS="$pos2"

# sanity
case "$CORES" in *[!0-9]*|'') echo "Invalid cores: $CORES" >&2; exit 2;; esac
case "$SECS"  in *[!0-9]*|'') echo "Invalid seconds: $SECS" >&2; exit 2;; esac

log() { [ "$QUIET" -eq 1 ] || echo "$@"; }

# prefer stress-ng if present (unless --no-stress)
if [ "$USE_STRESS" != "no" ] && command -v stress-ng >/dev/null 2>&1; then
  log "Using stress-ng: --cpu $CORES --timeout ${SECS}s"
  exec stress-ng --cpu "$CORES" --timeout "${SECS}s"
fi

# fallback: spawn busy loops, pin if taskset exists
CPU_TOTAL="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
PIDS=""
cleanup() { kill $PIDS 2>/dev/null || true; wait $PIDS 2>/dev/null || true; }
trap cleanup INT TERM EXIT

i=0
while [ "$i" -lt "$CORES" ]; do
  i=$((i+1))
  if command -v taskset >/dev/null 2>&1; then
    core=$(( (i-1) % CPU_TOTAL ))
    taskset -c "$core" sh -c 'yes > /dev/null' &
  else
    sh -c 'yes > /dev/null' &
  fi
  PIDS="$PIDS $!"
done

log "Fallback: started $CORES worker(s) for ${SECS}s (pinning: $(command -v taskset >/dev/null 2>&1 && echo on || echo off))"
sleep "$SECS"
cleanup
log "Done."

