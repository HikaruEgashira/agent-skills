#!/usr/bin/env bash
# agentops dreaming -- Stop-hook DISPATCHER.
#
# Contract (verified ground truth):
#   - stdin JSON: { session_id, transcript_path, cwd, permission_mode,
#                   hook_event_name:"Stop", stop_hook_active:bool }
#   - MUST exit 0 quickly (<1s). MUST NOT block the reply. MUST NOT print a
#     "block" decision. Errors go ONLY to the diagnostics log.
#
# Responsibilities:
#   1. kill switch / loop guard / prereqs.
#   2. resolve memory dir; require it to exist and be non-empty.
#   3. rate gate.
#   4. NEW-MEMORY trigger gate via fingerprint delta (empty -> commit fp, exit).
#   5. acquire lock, detach worker (nohup+disown, no setsid), exit 0.
#
# The dispatcher NEVER calls the model. It passes ONLY paths/ids to the worker
# via AGENTOPS_RT_* env vars -- never interpolates untrusted content into a
# command string. (Injection-safe shell.)

set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
LIB="${PLUGIN_ROOT}/scripts/dream-lib.sh"
WORKER="${PLUGIN_ROOT}/scripts/dream-worker.sh"

# Source lib; if missing, fail safe.
# shellcheck source=/dev/null
. "$LIB" 2>/dev/null || exit 0

# --- kill switch -----------------------------------------------------------
[ "$(cfg_disable)" = "1" ] && exit 0

# --- prereqs: jq -----------------------------------------------------------
command -v jq >/dev/null 2>&1 || { log "skip: jq not found"; exit 0; }

# --- read stdin ------------------------------------------------------------
STDIN_JSON=$(cat 2>/dev/null)
[ -n "$STDIN_JSON" ] || exit 0

# --- loop safety -----------------------------------------------------------
STOP_ACTIVE=$(printf '%s' "$STDIN_JSON" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

CWD=$(printf '%s' "$STDIN_JSON" | jq -r '.cwd // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$STDIN_JSON" | jq -r '.session_id // empty' 2>/dev/null)

# --- resolve + require memory dir ------------------------------------------
MEMDIR=$(memory_dir_from_cwd "$CWD" 2>/dev/null)
[ -n "$MEMDIR" ] || { log "skip: no memory dir (cwd empty)"; exit 0; }
[ -d "$MEMDIR" ] || { log "skip: memory dir absent: $MEMDIR"; exit 0; }

# any *.md other than MEMORY.md?
HAVE_ENTRY=0
for f in "$MEMDIR"/*.md; do
  [ -e "$f" ] || continue
  case "$(basename "$f")" in MEMORY.md) continue ;; esac
  HAVE_ENTRY=1; break
done
[ "$HAVE_ENTRY" = "1" ] || { log "skip: no memory entries in $MEMDIR"; exit 0; }

# --- rate gate -------------------------------------------------------------
rate_ok "$MEMDIR" || { log "skip: rate gate ($MEMDIR)"; exit 0; }

# --- resolve claude bin (fail closed if absent) ----------------------------
CLAUDE_BIN=$(claude_bin) || { log "skip: claude binary not found"; exit 0; }

# --- trigger gate: fingerprint delta ---------------------------------------
STATE_DIR=$(state_dir_for "$MEMDIR")
mkdir -p "$STATE_DIR" 2>/dev/null || true
FP_OLD="${STATE_DIR}/fingerprint"
FP_CUR=$(mktemp "${STATE_DIR}/fp.cur.XXXXXX" 2>/dev/null) || { log "skip: mktemp failed"; exit 0; }
DELTA_F=$(mktemp "${STATE_DIR}/fp.delta.XXXXXX" 2>/dev/null) || { rm -f "$FP_CUR"; exit 0; }

fingerprint "$MEMDIR" >"$FP_CUR" 2>/dev/null
fingerprint_delta "$FP_CUR" "$FP_OLD" >"$DELTA_F" 2>/dev/null

if [ ! -s "$DELTA_F" ]; then
  # no new/changed entries -> no dream. Commit current fp so the baseline
  # stays fresh, then exit.
  cp -f "$FP_CUR" "$FP_OLD" 2>/dev/null || true
  rm -f "$FP_CUR" "$DELTA_F" 2>/dev/null || true
  log "no-op: empty delta ($MEMDIR)"
  exit 0
fi

# --- acquire lock ----------------------------------------------------------
LOCKDIR=$(lock_acquire "$MEMDIR") || { log "skip: lock busy ($MEMDIR)"; rm -f "$FP_CUR" "$DELTA_F" 2>/dev/null; exit 0; }

# Hand the delta file to the worker (do NOT remove it here).
RT_DELTA="${STATE_DIR}/delta.active"
mv -f "$DELTA_F" "$RT_DELTA" 2>/dev/null || cp -f "$DELTA_F" "$RT_DELTA" 2>/dev/null
rm -f "$FP_CUR" 2>/dev/null || true

# --- detach worker ---------------------------------------------------------
# Pass ONLY safe scalars (paths/ids) via env. No content interpolation.
export AGENTOPS_RT_MEMDIR="$MEMDIR"
export AGENTOPS_RT_LOCKDIR="$LOCKDIR"
export AGENTOPS_RT_DELTA="$RT_DELTA"
export AGENTOPS_RT_STATE_DIR="$STATE_DIR"
export AGENTOPS_RT_CLAUDE_BIN="$CLAUDE_BIN"
export AGENTOPS_RT_SESSION_ID="$SESSION_ID"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

if [ ! -x "$WORKER" ]; then
  log "skip: worker not executable: $WORKER"
  lock_release "$LOCKDIR"
  rm -f "$RT_DELTA" 2>/dev/null
  exit 0
fi

# Detach (macOS: no setsid). nohup + disown; stdin closed; output -> log.
nohup "$WORKER" >>"$LOG_FILE" 2>&1 </dev/null &
disown 2>/dev/null || true

log "dispatched worker ($MEMDIR)"
exit 0
