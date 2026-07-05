#!/usr/bin/env bash
# Regression tests for the dreaming worker's fail-closed body handling.
#
# Locks the invariant: when the model output is null / empty / whitespace /
# non-JSON / a drastically-shrunk body, the target memory entry stays
# BYTE-IDENTICAL. (Incident 2026-07-05: "new_body": null was written back as
# the literal body "null", destroying a ~1500-char entry.)
#
# Run:  bash agentops/scripts/tests/dream-worker-test.sh
# Deps: bash 3.2+, jq, coreutils. No network, no real claude binary.

set -u

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT=$(cd "${TESTS_DIR}/../.." && pwd)
WORKER="${PLUGIN_ROOT}/scripts/dream-worker.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not found"; exit 0; }
[ -f "$WORKER" ] || { echo "FAIL: worker not found at $WORKER"; exit 1; }

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/agentops-dream-test.XXXXXX") || exit 1
trap 'rm -rf "$SANDBOX"' EXIT INT TERM

# Sandbox HOME so logs/state never touch the real ~/.claude.
export HOME="$SANDBOX/home"
MEMDIR="$SANDBOX/memory"
STATE_DIR="$SANDBOX/state"
mkdir -p "$HOME" "$MEMDIR" "$STATE_DIR"

# --- fake claude binary: swallows stdin, prints $FAKE_RESPONSE_FILE ---------
FAKE_BIN="$SANDBOX/fake-claude"
cat >"$FAKE_BIN" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
[ -n "${FAKE_RESPONSE_FILE:-}" ] && [ -f "$FAKE_RESPONSE_FILE" ] && cat "$FAKE_RESPONSE_FILE"
exit 0
EOF
chmod +x "$FAKE_BIN"

# --- fixture entry (body must be >= 200 bytes to arm the shrink guard) ------
ENTRY_ID="test-entry"
ENTRY="$MEMDIR/${ENTRY_ID}.md"
make_entry() {
  cat >"$ENTRY" <<'EOF'
---
name: test-entry
description: fixture entry for dream-worker regression tests
metadata:
  type: project
---
# Fixture body

This body simulates a real memory entry. It is intentionally longer than two
hundred bytes so the shrink guard is armed. Refinement-only means this content
may be sharpened but never wiped, nulled, or drastically truncated by the
offline dreaming pass. Line two of substantive content to pad the fixture out
past the guard threshold with realistic prose rather than filler characters.
EOF
}

# --- helpers ----------------------------------------------------------------
FAILURES=0
run_worker() {
  # run_worker RESPONSE_FILE -- invoke the worker synchronously with fresh
  # lock/delta (the worker consumes both on every run).
  local resp="$1" lockdir="$SANDBOX/lock" delta="$SANDBOX/delta"
  mkdir -p "$lockdir"
  printf '%s\n' "$ENTRY_ID" >"$delta"
  FAKE_RESPONSE_FILE="$resp" \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  AGENTOPS_RT_MEMDIR="$MEMDIR" \
  AGENTOPS_RT_LOCKDIR="$lockdir" \
  AGENTOPS_RT_DELTA="$delta" \
  AGENTOPS_RT_STATE_DIR="$STATE_DIR" \
  AGENTOPS_RT_CLAUDE_BIN="$FAKE_BIN" \
  AGENTOPS_RT_CWD="$SANDBOX" \
  AGENTOPS_DREAM_MIRROR_AGENTS=0 \
  bash "$WORKER" >/dev/null 2>&1
}

envelope_with_ops() {
  # envelope_with_ops OPS_JSON OUTFILE -- wrap ops JSON in the `claude -p
  # --output-format json` result envelope, as the worker receives it.
  jq -n --arg r "$1" '{result: $r}' >"$2"
}

assert_unchanged() {
  # assert_unchanged NAME SNAPSHOT -- entry must be byte-identical to snapshot.
  if cmp -s "$2" "$ENTRY"; then
    echo "PASS: $1 (entry byte-identical)"
  else
    echo "FAIL: $1 (entry was modified)"
    diff -u "$2" "$ENTRY" | head -20
    FAILURES=$((FAILURES + 1))
  fi
}

update_op_with_body() {
  # update_op_with_body BODY_JSON -- ops payload proposing new_body=BODY_JSON.
  printf '{"ops":[{"op":"update","target_ids":["%s"],"new_name":null,"new_frontmatter":null,"new_body":%s,"links":[],"confidence":0.95,"rationale":"test"}],"summary":"test"}' \
    "$ENTRY_ID" "$1"
}

# --- destructive-input cases: entry must stay byte-identical -----------------
run_case_unchanged() {
  local name="$1" resp="$2" snap="$SANDBOX/snap"
  make_entry
  cp -f "$ENTRY" "$snap"
  run_worker "$resp"
  assert_unchanged "$name" "$snap"
}

R="$SANDBOX/resp"

envelope_with_ops "$(update_op_with_body 'null')" "$R.null"
run_case_unchanged "new_body is JSON null" "$R.null"

envelope_with_ops "$(update_op_with_body '""')" "$R.empty"
run_case_unchanged "new_body is empty string" "$R.empty"

envelope_with_ops "$(update_op_with_body '"   \n\t  "')" "$R.blank"
run_case_unchanged "new_body is whitespace-only" "$R.blank"

envelope_with_ops "$(update_op_with_body '"null"')" "$R.litnull"
run_case_unchanged "new_body is the literal string null" "$R.litnull"

envelope_with_ops "$(update_op_with_body '"tiny."')" "$R.shrunk"
run_case_unchanged "new_body drastically shorter than original" "$R.shrunk"

jq -n '{result: "Sorry, I cannot produce JSON for that request."}' >"$R.prose"
run_case_unchanged "model output is prose, not JSON ops" "$R.prose"

: >"$R.silent"
run_case_unchanged "model produced no output" "$R.silent"

envelope_with_ops '{"ops": "not-an-array"}' "$R.badops"
run_case_unchanged "ops field is not an array" "$R.badops"

# degenerate merge (targets collapse to the survivor) must be a strict no-op.
envelope_with_ops "$(printf '{"ops":[{"op":"merge","target_ids":["%s","%s"],"new_name":null,"new_frontmatter":null,"new_body":null,"links":[],"confidence":0.95,"rationale":"test"}],"summary":"t"}' "$ENTRY_ID" "$ENTRY_ID")" "$R.mergeself"
run_case_unchanged "merge op with no real losers" "$R.mergeself"

# merge with a real loser but null new_body must leave BOTH entries untouched
# (deleting the loser without merged content would discard its facts).
OTHER_ID="other-entry"
OTHER="$MEMDIR/${OTHER_ID}.md"
cat >"$OTHER" <<'EOF'
---
name: other-entry
description: second fixture entry, near-duplicate of the first fixture
metadata:
  type: project
---
Loser candidate. Mentions fixture so the dup-candidate scan selects it.
EOF
make_entry
SNAP_A="$SANDBOX/snap-a"; SNAP_B="$SANDBOX/snap-b"
cp -f "$ENTRY" "$SNAP_A"; cp -f "$OTHER" "$SNAP_B"
envelope_with_ops "$(printf '{"ops":[{"op":"merge","target_ids":["%s","%s"],"new_name":null,"new_frontmatter":null,"new_body":null,"links":[],"confidence":0.95,"rationale":"test"}],"summary":"t"}' "$ENTRY_ID" "$OTHER_ID")" "$R.mergenull"
run_worker "$R.mergenull"
if cmp -s "$SNAP_A" "$ENTRY" && [ -f "$OTHER" ] && cmp -s "$SNAP_B" "$OTHER"; then
  echo "PASS: merge with real loser and null new_body (both entries byte-identical)"
else
  echo "FAIL: merge with real loser and null new_body modified or deleted an entry"
  FAILURES=$((FAILURES + 1))
fi
rm -f "$OTHER"

# --- positive control: a real refinement must still apply --------------------
make_entry
GOOD_BODY='# Fixture body (refined)\n\nREFINED-BODY-MARKER: this replacement is a legitimate refinement. It keeps the substance of the original fixture entry, stays comfortably above half the original body size to clear the shrink guard, and proves that the fail-closed guards do not block genuine refinement operations proposed by the dreaming model.'
envelope_with_ops "$(update_op_with_body "\"$GOOD_BODY\"")" "$R.good"
SNAP="$SANDBOX/snap"
cp -f "$ENTRY" "$SNAP"
run_worker "$R.good"
if cmp -s "$SNAP" "$ENTRY"; then
  echo "FAIL: legitimate refinement was blocked (entry unchanged)"
  FAILURES=$((FAILURES + 1))
elif grep -q 'REFINED-BODY-MARKER' "$ENTRY"; then
  echo "PASS: legitimate refinement applied"
else
  echo "FAIL: entry changed but refined body missing"
  FAILURES=$((FAILURES + 1))
fi

# ---------------------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  echo "RESULT: $FAILURES failure(s)"
  exit 1
fi
echo "RESULT: all tests passed"
exit 0
