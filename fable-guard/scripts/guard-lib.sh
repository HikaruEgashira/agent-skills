#!/usr/bin/env bash
# fable-guard -- shared library for the refusal-recovery Stop hook.
#
# Fable 5 runs safety classifiers (cybersecurity / biology). When a request is
# flagged AND `switchModelsOnFlag: false` is set, Claude Code does NOT fall back
# to Opus: the turn ends with a refusal and the transcript records a system
# entry `subtype: "model_refusal_no_fallback"`. This library detects that state
# and drives recovery (context compaction + reprompt) through the herdr socket
# API, which is the only actuator able to inject a slash command into the live
# TUI (hooks themselves cannot trigger `/` commands).
#
# All functions are side-effect-light and fail closed: any missing prereq makes
# the caller skip recovery rather than block the reply.

# --- config (env-overridable, safe defaults) -------------------------------
cfg_disable()      { printf '%s' "${FABLE_GUARD_DISABLE:-0}"; }
cfg_mode()         { printf '%s' "${FABLE_GUARD_MODE:-recover}"; }        # recover | notify
cfg_max_retries()  { printf '%s' "${FABLE_GUARD_MAX_RETRIES:-2}"; }
cfg_compact()      { printf '%s' "${FABLE_GUARD_COMPACT:-1}"; }           # 1 = run /compact first
cfg_reprompt()     { printf '%s' "${FABLE_GUARD_REPROMPT:-}"; }           # non-empty = fixed reprompt text

# --- paths -----------------------------------------------------------------
_state_root() {
  printf '%s/fable-guard' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

# Per-session state dir. Keyed by session id so retry counters never collide
# between concurrent herdr panes.
state_dir_for() {
  sid="$1"
  [ -n "$sid" ] || sid="unknown"
  printf '%s/%s' "$(_state_root)" "$sid"
}

LOG_FILE="$(_state_root)/log"

log() {
  # Best-effort diagnostics only. Never fail the hook because logging failed.
  d="$(_state_root)"
  mkdir -p "$d" 2>/dev/null || return 0
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo '?')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

# --- herdr environment -----------------------------------------------------
# We can only recover inside a herdr session: recovery injects keystrokes into
# the pane that owns this Claude process.
herdr_ok() {
  [ "${HERDR_ENV:-}" = "1" ] || return 1
  [ -n "${HERDR_SOCKET_PATH:-}" ] || return 1
  [ -S "${HERDR_SOCKET_PATH:-/nonexistent}" ] || return 1
  command -v herdr >/dev/null 2>&1 || return 1
  return 0
}

# Resolve the pane id for this session. Prefer the inherited HERDR_PANE_ID
# (this process' own pane); fall back to matching session_id against the
# herdr agent list so recovery still targets the right pane if the env var is
# absent (e.g. a detached worker that lost it).
herdr_pane_for_session() {
  sid="$1"
  if [ -n "${HERDR_PANE_ID:-}" ]; then
    printf '%s' "$HERDR_PANE_ID"; return 0
  fi
  [ -n "$sid" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  herdr agent list 2>/dev/null \
    | jq -r --arg s "$sid" \
        '.result.agents[]? | select(.agent_session.value == $s) | .pane_id' 2>/dev/null \
    | head -n1 | grep . || return 1
}

# --- transcript inspection -------------------------------------------------
# True (exit 0) when the LAST typed user turn was answered with a
# no-fallback refusal, i.e. the most recent `model_refusal_no_fallback` system
# entry appears after the most recent `promptSource == "typed"` user entry.
# Reading only the tail keeps this cheap even on long transcripts.
transcript_refused() {
  tp="$1"
  [ -f "$tp" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  # Walk the tail; track line index of last typed user prompt and last refusal.
  tail -n 400 "$tp" 2>/dev/null | jq -rs '
    . as $arr
    | (reduce range(0; ($arr | length)) as $i (
        {u: -1, r: -1};
        ($arr[$i]) as $e
        | if ($e.type == "user" and $e.promptSource == "typed") then .u = $i
          elif ($e.type == "system"
                 and ($e.subtype == "model_refusal_no_fallback"
                      or $e.subtype == "model_refusal_fallback")) then .r = $i
          else . end
     )) as $s
    | if ($s.r > $s.u and $s.r >= 0) then "refused" else "ok" end
  ' 2>/dev/null | grep -q '^refused$'
}

# Extract the text of the most recent typed user prompt, flattened to a single
# line (herdr send-keys enter submits on newline, so multi-line text would be
# submitted mid-prompt). Truncated to a sane length. Empty output on failure.
transcript_last_typed_prompt() {
  tp="$1"
  [ -f "$tp" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  tail -n 400 "$tp" 2>/dev/null | jq -rs '
    [ .[] | select(.type == "user" and .promptSource == "typed") ] | last
    | (.message.content) as $c
    | if ($c | type) == "string" then $c
      elif ($c | type) == "array" then
        ([ $c[] | select(.type == "text") | .text ] | join(" "))
      else "" end
  ' 2>/dev/null \
    | tr '\n\r\t' '   ' | sed 's/  */ /g; s/^ //; s/ $//' | cut -c1-2000
}
