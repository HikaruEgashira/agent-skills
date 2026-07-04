#!/usr/bin/env bash
# fable-guard -- detached recovery WORKER.
#
# Invoked by refusal-dispatch.sh with FG_RT_* env vars already set. Runs in the
# background so the Stop hook can exit immediately. Drives recovery through the
# herdr socket API:
#
#   notify mode (or retry cap reached):
#     post a notification / desktop alert only; do not touch the prompt.
#
#   recover mode:
#     1. wait for the pane to go idle (input-ready),
#     2. optionally run /compact and wait for it to finish,
#     3. resubmit the last typed prompt,
#     4. bump the per-session retry counter.
#
# The lock (FG_RT_LOCKDIR) is held for the whole run and released on exit, so
# only one recovery is ever in flight per session.

set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
# shellcheck source=/dev/null
. "${PLUGIN_ROOT}/scripts/guard-lib.sh" 2>/dev/null || exit 0

PANE="${FG_RT_PANE:-}"
SESSION_ID="${FG_RT_SESSION_ID:-}"
STATE_DIR="${FG_RT_STATE_DIR:-}"
LOCKDIR="${FG_RT_LOCKDIR:-}"
REPROMPT_F="${FG_RT_REPROMPT_F:-}"
COUNT_F="${FG_RT_COUNT_F:-}"
COUNT="${FG_RT_COUNT:-0}"
FORCE_NOTIFY="${FG_RT_FORCE_NOTIFY:-0}"

cleanup() { [ -n "$LOCKDIR" ] && rmdir "$LOCKDIR" 2>/dev/null || true; }
trap cleanup EXIT HUP INT TERM

[ -n "$PANE" ] || { log "worker: no pane; abort"; exit 0; }

notify() {
  msg="$1"
  # Prefer herdr's own notification channel; fall back to macOS notification.
  herdr notification post --title "fable-guard" --message "$msg" >/dev/null 2>&1 && return 0
  command -v osascript >/dev/null 2>&1 \
    && osascript -e "display notification \"${msg}\" with title \"fable-guard\"" >/dev/null 2>&1
  return 0
}

# --- notify-only paths -----------------------------------------------------
if [ "$(cfg_mode)" = "notify" ]; then
  notify "Fable request was flagged (refusal). Edit the prompt and retry, or /model to switch."
  log "worker: notify mode; done"
  exit 0
fi
if [ "$FORCE_NOTIFY" = "1" ]; then
  notify "Fable refusal persisted after ${COUNT} auto-retries. Stopping auto-recovery for this session."
  log "worker: retry cap reached; notify only"
  exit 0
fi

# --- recover: wait until the pane can accept input -------------------------
herdr agent wait "$PANE" --status idle --timeout 20000 >/dev/null 2>&1 || {
  log "worker: pane not idle within timeout; abort"
  exit 0
}

# --- optional /compact -----------------------------------------------------
if [ "$(cfg_compact)" = "1" ]; then
  log "worker: sending /compact to $PANE"
  herdr pane send-text "$PANE" "/compact" >/dev/null 2>&1
  herdr pane send-keys "$PANE" enter >/dev/null 2>&1
  # Let it start, then wait for it to return to idle. compact can be slow.
  herdr agent wait "$PANE" --status working --timeout 8000  >/dev/null 2>&1 || true
  herdr agent wait "$PANE" --status idle    --timeout 180000 >/dev/null 2>&1 || {
    log "worker: compact did not finish within timeout; abort before reprompt"
    exit 0
  }
fi

# --- resubmit the last typed prompt ----------------------------------------
REPROMPT="$(cat "$REPROMPT_F" 2>/dev/null)"
[ -n "$REPROMPT" ] || { log "worker: empty reprompt; abort"; exit 0; }

# Bump the counter BEFORE resubmitting: if the reprompt refuses again, the next
# Stop-hook pass sees the incremented count and honours the cap.
NEXT=$((COUNT + 1))
printf '%s' "$NEXT" >"$COUNT_F" 2>/dev/null || true

log "worker: resubmitting last typed prompt (attempt $NEXT) to $PANE"
herdr pane send-text "$PANE" "$REPROMPT" >/dev/null 2>&1
herdr pane send-keys "$PANE" enter >/dev/null 2>&1

log "worker: recovery submitted (session=$SESSION_ID attempt=$NEXT)"
exit 0
