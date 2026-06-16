#!/usr/bin/env bash
# lib/state.sh — shared primitives for the file bus.
# Sourced by ./bus. Targets bash 3.2 (macOS) — no associative arrays, no flock.
#
# Concurrency model: a single mkdir-based mutex serializes every mutation of
# state.json. mkdir is an atomic syscall, so exactly one process wins the race.
# Writes are atomic (jq -> temp file -> mv). Stale locks (dead holder PID) are
# reclaimed automatically.

# ---- paths (WS exported by ./bus) -------------------------------------------
: "${WS:?lib/state.sh: WS (workspace dir) must be set by caller}"
STATE="$WS/state.json"
LOCK_DIR="$WS/.locks/state.lock"
EVENT_LOG="$WS/event_log.md"
ERROR_DUMP="$WS/error_dump.md"
COMM_BUS="$WS/communication_bus.md"

LOCK_HELD=0

# ---- time helpers (UTC, cross-platform) -------------------------------------
now_epoch()   { date -u +%s; }
ts_compact()  { date -u +%dT%H%M; }   # e.g. 16T2240 — for buslang log lines

# Render an epoch as a short age like "3m" / "45s" / "2h" (no reverse parsing,
# so it works identically on BSD and GNU date).
age_of() {
  local then="$1" now diff
  now=$(now_epoch)
  diff=$((now - then))
  [ "$diff" -lt 0 ] && diff=0
  if   [ "$diff" -lt 60 ];   then echo "${diff}s"
  elif [ "$diff" -lt 3600 ]; then echo "$((diff/60))m"
  else echo "$((diff/3600))h"; fi
}

# ---- mutex -------------------------------------------------------------------
acquire_lock() {
  local waited=0 opid
  while :; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      echo "$$" > "$LOCK_DIR/pid"
      LOCK_HELD=1
      return 0
    fi
    # Lock dir exists. Reclaim it if the holder process is dead (stale lock).
    opid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ -n "$opid" ] && ! kill -0 "$opid" 2>/dev/null; then
      rm -rf "$LOCK_DIR"
      continue
    fi
    sleep 0.1
    waited=$((waited + 1))
    if [ "$waited" -ge 100 ]; then   # ~10s
      echo "bus: timeout acquiring lock (held by pid ${opid:-unknown})" >&2
      return 1
    fi
  done
}

release_lock() {
  if [ "${LOCK_HELD:-0}" = 1 ]; then
    rm -rf "$LOCK_DIR"
    LOCK_HELD=0
  fi
}
# Always release on exit/interrupt so a crashed command never wedges the bus.
trap release_lock EXIT INT TERM

# with_lock <fn> [args...] — run a mutation inside the critical section.
with_lock() {
  acquire_lock || return 1
  "$@"
  local rc=$?
  release_lock
  return $rc
}

# ---- atomic state write ------------------------------------------------------
# atomic_jq <jq-args...> — apply a jq filter to state.json and swap it in
# atomically. On jq failure the original file is left untouched.
atomic_jq() {
  local tmp="$STATE.tmp.$$"
  if jq "$@" "$STATE" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$STATE"
    return 0
  fi
  rm -f "$tmp"
  echo "bus: state transform failed (state.json unchanged)" >&2
  return 1
}

# ---- domain helpers ----------------------------------------------------------
# next_task_id — first free T-NNN across all status buckets.
next_task_id() {
  local max
  max=$(jq -r '[.tasks[][]?.id | ltrimstr("T-") | tonumber] | max // 0' "$STATE")
  printf 'T-%03d' "$((max + 1))"
}

require_state() {
  if [ ! -f "$STATE" ]; then
    echo "bus: $STATE not found — run './bus init' first" >&2
    return 1
  fi
  if ! jq -e . "$STATE" >/dev/null 2>&1; then
    echo "bus: $STATE is not valid JSON (corrupt). Run './bus doctor'." >&2
    return 1
  fi
}
