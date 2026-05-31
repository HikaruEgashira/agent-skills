#!/usr/bin/env bash
# agentops dreaming -- shared library sourced by dispatcher (dream.sh) and worker (dream-worker.sh).
#
# Design constraints (verified ground truth):
#   - bash 3.2 safe: no associative arrays, no mapfile, no `${var^^}`, no process-substitution reliance.
#   - runtime deps: jq + coreutils only. No python/yq/shellcheck at runtime.
#   - every helper is fail-safe; callers always exit 0.
#
# This file only DEFINES functions/vars; it performs no work on source.

# --------------------------------------------------------------------------
# config: env-driven with sane defaults. cfg() honors an explicitly-set var
# (even empty string) as intentional; only a TRULY-UNSET var falls back.
# Numeric getters coerce to digits and fall back when empty/non-numeric so a
# bad override (e.g. AGENTOPS_DREAM_TIMEOUT=fast) can never reach arithmetic
# or an external binary.  (Finding: cfg empty-string + unvalidated numerics.)
# --------------------------------------------------------------------------

cfg() {
  # cfg NAME DEFAULT  -> prints value; set-but-empty counts as set.
  local name="$1" def="$2"
  if [ "${!name+x}" = "x" ]; then
    printf '%s' "${!name}"
  else
    printf '%s' "$def"
  fi
}

cfg_num() {
  # cfg_num NAME DEFAULT  -> integer only; non-numeric/empty -> DEFAULT.
  local name="$1" def="$2" v
  v=$(cfg "$name" "$def")
  v=$(printf '%s' "$v" | tr -dc '0-9')
  [ -n "$v" ] || v="$def"
  printf '%s' "$v"
}

cfg_disable()    { cfg AGENTOPS_DREAM_DISABLE ""; }
cfg_model()      { cfg AGENTOPS_DREAM_MODEL "claude-haiku-4-5-20251001"; }
cfg_min_interval(){ cfg_num AGENTOPS_DREAM_MIN_INTERVAL 1800; }
cfg_max_per_day(){ cfg_num AGENTOPS_DREAM_MAX_PER_DAY 8; }
cfg_threshold()  { cfg AGENTOPS_DREAM_EVIDENCE_THRESHOLD "0.7"; }
cfg_promote()    { cfg AGENTOPS_DREAM_PROMOTE "apply"; }
cfg_timeout()    { cfg_num AGENTOPS_DREAM_TIMEOUT 120; }
cfg_memory_dir() { cfg AGENTOPS_DREAM_MEMORY_DIR ""; }
cfg_max_bytes()  { cfg_num AGENTOPS_DREAM_MAX_BYTES 60000; }
cfg_mirror()     { cfg AGENTOPS_DREAM_MIRROR_AGENTS "1"; }
cfg_max_destructive() { cfg_num AGENTOPS_DREAM_MAX_DESTRUCTIVE 6; }

# threshold as a 0-100 integer for bash 3.2 integer comparison.
threshold_centi() {
  local t; t=$(cfg_threshold)
  # accept 0.7 / .7 / 70 / 0 ; coerce to centi (0-100); default 70.
  t=$(printf '%s' "$t" | awk '
    { v=$0+0; if (v<=1 && v>0) v=v*100; if ($0=="0") v=0;
      v=int(v+0.5); if (v<0) v=0; if (v>100) v=100; print v }')
  [ -n "$t" ] || t=70
  printf '%s' "$t"
}

# --------------------------------------------------------------------------
# logging + secret hygiene
# --------------------------------------------------------------------------

LOG_DIR="${HOME}/.claude/agentops"
LOG_FILE="${LOG_DIR}/dream.log"

log() {
  # log MESSAGE... -> appends a redacted, timestamped line. Never fails.
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "?")
  printf '%s %s\n' "$ts" "$*" | redact >>"$LOG_FILE" 2>/dev/null || true
}

# redact: AGGRESSIVE masker for the LOG and for the DATA region sent to the
# model. Broadened well beyond the original key-name-only rule.
# (Findings: generic/.env/url-cred secrets unredacted.)
#
# NOTE: a separate, CONSERVATIVE masker (redact_write) is used for content
# written BACK into memory files, to avoid mangling ordinary prose.
redact() {
  sed -E \
    -e 's#(://[^:/@[:space:]]+):[^@/[:space:]]+@#\1:[REDACTED]@#g' \
    -e 's/AKIA[0-9A-Z]{16}/[REDACTED_AWS_KEY]/g' \
    -e 's/ASIA[0-9A-Z]{16}/[REDACTED_AWS_KEY]/g' \
    -e 's/(gh[pousr]_)[A-Za-z0-9]{20,}/\1[REDACTED]/g' \
    -e 's/github_pat_[A-Za-z0-9_]{20,}/[REDACTED_PAT]/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED_SLACK]/g' \
    -e 's/sk-[A-Za-z0-9_-]{16,}/[REDACTED_SK]/g' \
    -e 's/(eyJ[A-Za-z0-9_-]{8,})\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/[REDACTED_JWT]/g' \
    -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----/[REDACTED_PRIVATE_KEY]/g' \
    -e 's/([Bb]earer )[A-Za-z0-9._-]{12,}/\1[REDACTED]/g' \
    -e 's/^([A-Z][A-Z0-9_]{2,}[[:space:]]*=[[:space:]]*).{8,}$/\1[REDACTED_VALUE]/g' \
    -e 's/([A-Za-z0-9_]*(secret|token|password|passwd|api[_-]?key|client[_-]?secret|access[_-]?key|private[_-]?key|dsn)[A-Za-z0-9_]*[[:space:]]*[:=][[:space:]]*)"?[^"[:space:]]{6,}/\1[REDACTED_VALUE]/Ig' \
    2>/dev/null || cat
}

# redact_write: HIGH-PRECISION only -- for bytes written back into memory
# files. Drops the broad KEY=VALUE rule so legitimate prose like
# "the token: bearer of bad news" is not corrupted.
# (Finding: redact() corrupts non-secret body content.)
redact_write() {
  sed -E \
    -e 's#(://[^:/@[:space:]]+):[^@/[:space:]]+@#\1:[REDACTED]@#g' \
    -e 's/AKIA[0-9A-Z]{16}/[REDACTED_AWS_KEY]/g' \
    -e 's/ASIA[0-9A-Z]{16}/[REDACTED_AWS_KEY]/g' \
    -e 's/(gh[pousr]_)[A-Za-z0-9]{20,}/\1[REDACTED]/g' \
    -e 's/github_pat_[A-Za-z0-9_]{20,}/[REDACTED_PAT]/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED_SLACK]/g' \
    -e 's/sk-[A-Za-z0-9_-]{16,}/[REDACTED_SK]/g' \
    -e 's/(eyJ[A-Za-z0-9_-]{8,})\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/[REDACTED_JWT]/g' \
    -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----/[REDACTED_PRIVATE_KEY]/g' \
    2>/dev/null || cat
}

# secret_present: the OP REJECT GATE. Must be >= redact() so any op carrying a
# secret is rejected rather than silently masked. Covers the same generic
# KEY=VALUE / KEY: VALUE secret-name pattern plus the .env-shaped long value.
# (Finding: secret_present weaker than redact.)
secret_present() {
  # reads stdin; rc 0 if a secret-shape is found.
  grep -Eiq \
    -e '://[^:/@[:space:]]+:[^@/[:space:]]+@' \
    -e 'AKIA[0-9A-Z]{16}' \
    -e 'ASIA[0-9A-Z]{16}' \
    -e 'gh[pousr]_[A-Za-z0-9]{20,}' \
    -e 'github_pat_[A-Za-z0-9_]{20,}' \
    -e 'xox[baprs]-[A-Za-z0-9-]{10,}' \
    -e 'sk-[A-Za-z0-9_-]{16,}' \
    -e 'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}' \
    -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
    -e '[Bb]earer [A-Za-z0-9._-]{12,}' \
    -e '[A-Za-z0-9_]*(secret|token|password|passwd|api[_-]?key|client[_-]?secret|access[_-]?key|private[_-]?key|dsn)[A-Za-z0-9_]*[[:space:]]*[:=][[:space:]]*"?[^"[:space:]]{6,}' \
    -e '^[A-Z][A-Z0-9_]{2,}[[:space:]]*=[[:space:]]*.{12,}$' \
    2>/dev/null
}

# --------------------------------------------------------------------------
# binary resolution
# --------------------------------------------------------------------------

claude_bin() {
  # robust: aliases do not load in a non-interactive hook shell.
  local b
  # explicit override wins. Set AGENTOPS_DREAM_CLAUDE_BIN to an absolute path or a
  # name on PATH when the default `claudex`-first resolution points at an
  # unconfigured/non-headless wrapper. An override that resolves to nothing fails
  # closed (no dream) rather than silently falling back to a different binary.
  b="${AGENTOPS_DREAM_CLAUDE_BIN:-}"
  if [ -n "$b" ]; then
    if [ -x "$b" ]; then printf '%s' "$b"; return 0; fi
    b=$(command -v "$b" 2>/dev/null) && { printf '%s' "$b"; return 0; }
    return 1
  fi
  b=$(command -v claudex 2>/dev/null) && { printf '%s' "$b"; return 0; }
  b=$(command -v claude 2>/dev/null)  && { printf '%s' "$b"; return 0; }
  if [ -x "${HOME}/.claude/local/claude" ]; then
    printf '%s' "${HOME}/.claude/local/claude"; return 0
  fi
  return 1
}

timeout_bin() {
  local b
  b=$(command -v timeout 2>/dev/null)  && { printf '%s' "$b"; return 0; }
  b=$(command -v gtimeout 2>/dev/null) && { printf '%s' "$b"; return 0; }
  return 1
}

# --------------------------------------------------------------------------
# memory dir + state/staging dirs
# --------------------------------------------------------------------------

sanitize_cwd() {
  # absolute cwd -> Claude Code project-dir slug. Claude encodes both '/' and
  # '.' as '-' (e.g. /U/ghq/github.com/x -> -U-ghq-github-com-x), so we MUST
  # replace both or the derived memory dir misses every path containing a dot
  # (github.com, *.com, version dirs) and the Stop-hook gate silently no-ops.
  printf '%s' "$1" | sed -e 's#[/.]#-#g'
}

memory_dir_from_cwd() {
  # honor explicit override; else derive from cwd.
  local cwd="$1" ovr
  ovr=$(cfg_memory_dir)
  if [ -n "$ovr" ]; then printf '%s' "$ovr"; return 0; fi
  [ -n "$cwd" ] || return 1
  printf '%s/.claude/projects/%s/memory' "$HOME" "$(sanitize_cwd "$cwd")"
}

state_key() {
  # stable key for a memory dir path (used to namespace state/staging/lock).
  printf '%s' "$1" | sed -e 's#/#-#g' -e 's#^-##'
}

state_dir_for()   { printf '%s/state/%s' "$LOG_DIR" "$(state_key "$1")"; }
staging_dir_for() { printf '%s/staging/%s' "$LOG_DIR" "$(state_key "$1")"; }

# --------------------------------------------------------------------------
# slug + id safety
#   logical id  = frontmatter name (may contain spaces; in-file value only).
#   on-disk slug = sanitized, safe charset, used for FILENAME and [[token]].
# (Findings: path traversal, sed-injection, fingerprint churn, link parse.)
# --------------------------------------------------------------------------

ID_SAFE_RE='^[A-Za-z0-9._-]+$'

is_safe_id() {
  # rc 0 if arg is a safe bare slug (no /, no .., no leading dot/dash).
  case "$1" in
    ""|.|..) return 1 ;;
    */*|*..*) return 1 ;;
    .*|-*) return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq "$ID_SAFE_RE"
}

slugify() {
  # arbitrary text -> safe slug. Collapses unsafe chars to '-', trims,
  # lowercases nothing (preserve case), caps length, ensures non-empty.
  local s
  s=$(printf '%s' "$1" \
        | tr '\t\r\n' '   ' \
        | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/-+/-/g; s/^[-.]+//; s/[-.]+$//' \
        | cut -c1-80)
  [ -n "$s" ] || s="entry"
  printf '%s' "$s"
}

# --------------------------------------------------------------------------
# frontmatter parsing (between the first two '---' lines)
# --------------------------------------------------------------------------

fm_block() {
  # prints the frontmatter block (without the fences) of FILE.
  awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$1" 2>/dev/null
}

fm_field() {
  # fm_field FILE KEY (top-level scalar) -> value (trimmed, first match).
  local f="$1" k="$2"
  fm_block "$f" | awk -v k="$k" '
    $0 ~ "^"k"[[:space:]]*:" {
      sub("^"k"[[:space:]]*:[[:space:]]*","",$0)
      gsub(/^"|"$/,"",$0)
      print; exit
    }'
}

fm_type() {
  # metadata.type (nested) OR top-level type fallback.
  local f="$1" t
  t=$(fm_block "$f" | awk '
    /^metadata[[:space:]]*:/ {m=1; next}
    m && /^[^[:space:]]/ {m=0}
    m && /^[[:space:]]+type[[:space:]]*:/ {
      sub(/^[[:space:]]+type[[:space:]]*:[[:space:]]*/,"",$0)
      gsub(/^"|"$/,"",$0); print; exit
    }')
  [ -n "$t" ] || t=$(fm_field "$f" type)
  printf '%s' "$t"
}

fm_flagged() {
  # prints "1" if the entry is flagged (metadata.flagged: true or flagged: true).
  local f="$1" v
  v=$(fm_block "$f" | grep -Eo 'flagged[[:space:]]*:[[:space:]]*true' | head -n1)
  [ -n "$v" ] && printf '1' || printf '0'
}

entry_name_of() {
  # logical name (frontmatter name). tabs/newlines -> space; trimmed.
  local n
  n=$(fm_field "$1" name | tr '\t\r\n' '   ' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  [ -n "$n" ] || n=$(basename "$1" .md)
  printf '%s' "$n"
}

# entry_id_of: the STABLE identity used for fingerprint/index/links.
# Keyed on the ON-DISK FILENAME (slug), which is unique by construction and
# stable across content edits -- a name edit is a content-change of the same
# file, not delete+add. (Finding: fingerprint keyed on mutable name.)
entry_id_of() {
  basename "$1" .md
}

body_of() {
  # prints the body (everything after the closing frontmatter fence).
  awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{f=0;b=1;next} b{print}' "$1" 2>/dev/null
}

# --------------------------------------------------------------------------
# fingerprint + delta
#   id = on-disk slug (stable). MEMORY.md is EXCLUDED so the worker's own
#   index write never re-triggers a dream. Duplicate slugs are impossible
#   (filename is unique), so no silent collision.
# --------------------------------------------------------------------------

fingerprint() {
  # fingerprint MEMDIR -> lines "id<TAB>hash" sorted by id.
  local dir="$1" f id h
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in MEMORY.md) continue ;; esac
    id=$(entry_id_of "$f")
    h=$(redact <"$f" 2>/dev/null | shasum 2>/dev/null | awk '{print $1}')
    [ -n "$h" ] || h=$(redact <"$f" 2>/dev/null | cksum | awk '{print $1"-"$2}')
    printf '%s\t%s\n' "$id" "$h"
  done | sort
}

fingerprint_delta() {
  # fingerprint_delta CUR_FILE OLD_FILE -> ids that are NEW or CHANGED.
  # Deletions alone do NOT appear (we only emit ids present in CUR).
  local cur="$1" old="$2"
  if [ ! -s "$old" ]; then
    awk -F'\t' '{print $1}' "$cur"
    return 0
  fi
  # lines present in cur but not byte-identical in old -> id is new/changed.
  comm -23 <(sort "$cur") <(sort "$old") | awk -F'\t' '{print $1}' | sort -u
}

# --------------------------------------------------------------------------
# lock: atomic via mkdir; stale reclaim is race-safe via a per-pid token.
# (Finding: stale-lock TOCTOU allows two workers.)
# --------------------------------------------------------------------------

LOCK_STALE_SECS=900

_now() { date +%s 2>/dev/null || echo 0; }

lock_acquire() {
  # lock_acquire MEMDIR -> rc 0 and prints lockdir on success.
  local dir="$1" ld my_token tok_file lock_mtime now
  ld="$(state_dir_for "$dir")/lock"
  mkdir -p "$(dirname "$ld")" 2>/dev/null || true
  my_token="$$-$(_now)-$RANDOM"

  if mkdir "$ld" 2>/dev/null; then
    printf '%s\n' "$my_token" >"$ld/owner" 2>/dev/null || true
    printf '%s' "$ld"; return 0
  fi

  # lock exists -- check staleness.
  now=$(_now)
  lock_mtime=$(stat -f %m "$ld" 2>/dev/null || stat -c %Y "$ld" 2>/dev/null || echo "$now")
  if [ "$((now - lock_mtime))" -lt "$LOCK_STALE_SECS" ]; then
    return 1  # fresh lock held by someone else.
  fi

  # stale: attempt a race-safe reclaim. Use a uniquely-named claim dir so two
  # reclaimers cannot both believe they won.
  local claim="${ld}.reclaim.${my_token}"
  if ! mkdir "$claim" 2>/dev/null; then
    return 1
  fi
  rm -rf "$ld" 2>/dev/null || true
  if mkdir "$ld" 2>/dev/null; then
    printf '%s\n' "$my_token" >"$ld/owner" 2>/dev/null || true
    rm -rf "$claim" 2>/dev/null || true
    # verify ownership token round-trips (another reclaimer may have raced
    # between our rm and mkdir; if so, owner won't match).
    tok_file=$(cat "$ld/owner" 2>/dev/null)
    if [ "$tok_file" = "$my_token" ]; then
      printf '%s' "$ld"; return 0
    fi
    return 1
  fi
  rm -rf "$claim" 2>/dev/null || true
  return 1
}

lock_release() {
  # lock_release LOCKDIR
  [ -n "$1" ] && rm -rf "$1" 2>/dev/null || true
}

# --------------------------------------------------------------------------
# rate limiting: min interval + max/day, per memory-dir.
# --------------------------------------------------------------------------

rate_file_for() { printf '%s/rate' "$(state_dir_for "$1")"; }

rate_ok() {
  # rate_ok MEMDIR -> rc 0 if allowed by min-interval AND max/day.
  local dir="$1" rf last cnt day today now interval maxd
  rf=$(rate_file_for "$dir")
  interval=$(cfg_min_interval)
  maxd=$(cfg_max_per_day)
  now=$(_now)
  today=$(date -u +%Y%m%d 2>/dev/null || echo 0)
  last=0; cnt=0; day="$today"
  if [ -f "$rf" ]; then
    last=$(awk 'NR==1{print $1+0}' "$rf" 2>/dev/null)
    day=$(awk 'NR==2{print $1}' "$rf" 2>/dev/null)
    cnt=$(awk 'NR==3{print $1+0}' "$rf" 2>/dev/null)
    [ "$day" = "$today" ] || cnt=0
  fi
  if [ "$((now - last))" -lt "$interval" ]; then return 1; fi
  if [ "$cnt" -ge "$maxd" ]; then return 1; fi
  return 0
}

rate_record() {
  # rate_record MEMDIR -> bump last-run + daily counter.
  local dir="$1" rf last cnt day today now
  rf=$(rate_file_for "$dir")
  mkdir -p "$(dirname "$rf")" 2>/dev/null || true
  now=$(_now)
  today=$(date -u +%Y%m%d 2>/dev/null || echo 0)
  cnt=0; day="$today"
  if [ -f "$rf" ]; then
    day=$(awk 'NR==2{print $1}' "$rf" 2>/dev/null)
    cnt=$(awk 'NR==3{print $1+0}' "$rf" 2>/dev/null)
    [ "$day" = "$today" ] || cnt=0
  fi
  cnt=$((cnt + 1))
  printf '%s\n%s\n%s\n' "$now" "$today" "$cnt" >"$rf" 2>/dev/null || true
}

# --------------------------------------------------------------------------
# per-run backups + atomic writes
#   Backups go to a PER-RUN dir (BACKUP_DIR), snapshotted ONCE per file, so a
#   file touched by multiple ops keeps its true pre-run content.
# (Finding: single-generation .bak overwritten on multi-touch.)
# --------------------------------------------------------------------------

# BACKUP_DIR is set by the worker (mktemp -d) before any mutation.
backup_once() {
  # backup_once FILE -- snapshot pre-run content exactly once.
  local f="$1" b
  [ -n "$BACKUP_DIR" ] || return 0
  [ -e "$f" ] || return 0
  b="${BACKUP_DIR}/$(printf '%s' "$f" | sed 's#/#_#g').bak"
  [ -e "$b" ] && return 0
  cp -f "$f" "$b" 2>/dev/null || true
}

atomic_write() {
  # atomic_write DEST <stdin>  -- snapshot then temp+mv.
  local dest="$1" dir tmp
  dir=$(dirname "$dest")
  mkdir -p "$dir" 2>/dev/null || true
  backup_once "$dest"
  tmp=$(mktemp "${dir}/.dwtmp.XXXXXX" 2>/dev/null) || return 1
  cat >"$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$dest" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

atomic_rm() {
  # atomic_rm FILE -- snapshot then remove.
  local f="$1"
  [ -e "$f" ] || return 0
  backup_once "$f"
  rm -f "$f" 2>/dev/null || true
}

# --------------------------------------------------------------------------
# managed-block upsert: rewrite ONLY between markers; never touch the rest.
# --------------------------------------------------------------------------

managed_block_upsert() {
  # managed_block_upsert FILE START END <stdin=block-content>
  # If file lacks the markers, append a fresh block. Atomic.
  local file="$1" start="$2" end="$3" content dir tmp
  content=$(cat)
  dir=$(dirname "$file")
  mkdir -p "$dir" 2>/dev/null || true
  backup_once "$file"
  tmp=$(mktemp "${dir}/.dwblk.XXXXXX" 2>/dev/null) || return 1

  if [ -f "$file" ] && grep -qF "$start" "$file" 2>/dev/null && grep -qF "$end" "$file" 2>/dev/null; then
    # awk getline-from-file needs the replacement body on disk first.
    printf '%s\n' "$content" >"$tmp.body" 2>/dev/null
    awk -v s="$start" -v e="$end" -v cf="$tmp.body" '
      BEGIN{ skip=0 }
      index($0,s){ print; while((getline line < cf)>0) print line; close(cf); skip=1; next }
      index($0,e){ skip=0; print; next }
      skip==1 { next }
      { print }
    ' "$file" >"$tmp" 2>/dev/null
    rm -f "$tmp.body" 2>/dev/null
  else
    { [ -f "$file" ] && cat "$file"; printf '\n%s\n%s\n%s\n' "$start" "$content" "$end"; } >"$tmp" 2>/dev/null
  fi
  mv -f "$tmp" "$file" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}
