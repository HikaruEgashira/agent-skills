#!/usr/bin/env bash
# fable-guard -- Stop-hook DISPATCHER.
#
# Contract:
#   - stdin JSON: { session_id, transcript_path, cwd, hook_event_name:"Stop",
#                   stop_hook_active:bool, ... }
#   - MUST exit 0 quickly. MUST NOT block the reply. MUST NOT print a "block"
#     decision. Diagnostics go ONLY to the log file.
#
# Responsibilities:
#   1. kill switch / prereqs / loop guard.
#   2. require a herdr session (recovery needs the socket actuator).
#   3. detect a no-fallback refusal on the last typed turn; else exit.
#   4. enforce the per-session retry cap.
#   5. capture the reprompt text, acquire a lock, detach the worker, exit 0.
#
# The dispatcher NEVER injects keystrokes itself and NEVER interpolates
# transcript content into a command: it writes the reprompt to a file and
# passes ONLY paths/ids to the worker via FG_RT_* env vars.

set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
LIB="${PLUGIN_ROOT}/scripts/guard-lib.sh"
WORKER="${PLUGIN_ROOT}/scripts/refusal-recover.sh"

# shellcheck source=/dev/null
. "$LIB" 2>/dev/null || exit 0

[ "$(cfg_disable)" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || { log "skip: jq not found"; exit 0; }

STDIN_JSON=$(cat 2>/dev/null)
[ -n "$STDIN_JSON" ] || exit 0

# Loop safety: never react to a turn that a Stop hook itself continued.
STOP_ACTIVE=$(printf '%s' "$STDIN_JSON" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

TRANSCRIPT=$(printf '%s' "$STDIN_JSON" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$STDIN_JSON" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$TRANSCRIPT" ] || { log "skip: no transcript_path"; exit 0; }

# Recovery is only possible inside a herdr session.
herdr_ok || { log "skip: not in a herdr session"; exit 0; }

# Detect the refusal state before spending any more effort.
transcript_refused "$TRANSCRIPT" || exit 0
log "detected no-fallback refusal (session=$SESSION_ID)"

# Resolve the target pane now (fail closed if we cannot).
PANE=$(herdr_pane_for_session "$SESSION_ID") || { log "skip: cannot resolve pane"; exit 0; }
[ -n "$PANE" ] || { log "skip: empty pane id"; exit 0; }

# --- capture reprompt text (needed before the retry cap, to key the counter) -
STATE_DIR=$(state_dir_for "$SESSION_ID")
mkdir -p "$STATE_DIR" 2>/dev/null || { log "skip: mkdir state failed"; exit 0; }
REPROMPT_F="${STATE_DIR}/reprompt.txt"
FIXED=$(cfg_reprompt)
if [ -n "$FIXED" ]; then
  printf '%s' "$FIXED" >"$REPROMPT_F" 2>/dev/null
else
  transcript_last_typed_prompt "$TRANSCRIPT" >"$REPROMPT_F" 2>/dev/null || true
fi
[ -s "$REPROMPT_F" ] || { log "skip: empty reprompt"; exit 0; }

# --- per-session retry cap, keyed to the offending prompt ------------------
# The counter tracks retries of ONE prompt. When a different typed prompt
# refuses, reset the counter so a fresh piece of work gets its own budget.
COUNT_F="${STATE_DIR}/retry.count"
HASH_F="${STATE_DIR}/retry.key"
CUR_HASH=$(cksum "$REPROMPT_F" 2>/dev/null | awk '{print $1}')
OLD_HASH=$(cat "$HASH_F" 2>/dev/null || echo '')
if [ "$CUR_HASH" != "$OLD_HASH" ]; then
  printf '%s' "$CUR_HASH" >"$HASH_F" 2>/dev/null || true
  printf '0' >"$COUNT_F" 2>/dev/null || true
fi
COUNT=$(cat "$COUNT_F" 2>/dev/null || echo 0)
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
MAX=$(cfg_max_retries); case "$MAX" in ''|*[!0-9]*) MAX=2 ;; esac
if [ "$COUNT" -ge "$MAX" ]; then
  log "cap reached (count=$COUNT max=$MAX); notify-only"
  # Fall through to worker in notify mode so the user is told, but do not retry.
  FORCE_NOTIFY=1
else
  FORCE_NOTIFY=0
fi

# --- single-flight lock ----------------------------------------------------
LOCKDIR="${STATE_DIR}/lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  log "skip: recovery already in flight (session=$SESSION_ID)"
  exit 0
fi

# --- detach worker ---------------------------------------------------------
# Pass ONLY safe scalars (paths/ids) via env. No content interpolation.
export FG_RT_PANE="$PANE"
export FG_RT_SESSION_ID="$SESSION_ID"
export FG_RT_TRANSCRIPT="$TRANSCRIPT"
export FG_RT_STATE_DIR="$STATE_DIR"
export FG_RT_LOCKDIR="$LOCKDIR"
export FG_RT_REPROMPT_F="$REPROMPT_F"
export FG_RT_COUNT_F="$COUNT_F"
export FG_RT_COUNT="$COUNT"
export FG_RT_FORCE_NOTIFY="$FORCE_NOTIFY"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

if [ ! -x "$WORKER" ]; then
  log "skip: worker not executable: $WORKER"
  rmdir "$LOCKDIR" 2>/dev/null
  exit 0
fi

# Detach (macOS: no setsid). nohup + disown; stdin closed; output -> log.
nohup "$WORKER" >>"$LOG_FILE" 2>&1 </dev/null &
disown 2>/dev/null || true

log "dispatched recovery worker (session=$SESSION_ID pane=$PANE notify=$FORCE_NOTIFY)"
exit 0
