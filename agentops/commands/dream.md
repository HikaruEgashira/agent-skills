---
description: 既存メモリの精緻化パス (dreaming) を手動で 1 回実行する。trigger gate をバイパスするが refinement-only は不変。
---

# /dream — オンデマンドの記憶整理 (refinement-only)

agentops dreaming の精緻化パスを **今すぐ 1 回** 実行します。通常は Stop hook が新規記憶を
検知したときだけ発火しますが、このコマンドは **trigger gate をバイパス**して即時に走らせます。
精緻化のみ (既存メモリの統合・明確化・リンク・flag) で、transcript は読まず新しい事実も
作りません。

## 実行手順

1. `${CLAUDE_PLUGIN_ROOT}` または agentops プラグインの `scripts/` を解決する。
2. 現在の cwd からメモリディレクトリを導出する:
   `~/.claude/projects/<cwd の "/" を "-" に置換>/memory`
   (`AGENTOPS_DREAM_MEMORY_DIR` があればそれを優先)。ディレクトリが無ければ「整理対象なし」と
   報告して終了。
3. worker を **同期** (前景) で起動し、メモリディレクトリ全体を FOCUS として精緻化させる。
   delta gate はバイパスするが、その他の安全機構 (lock / evidence threshold / .bak + atomic /
   secret redaction / 最小権限モデル呼び出し / audit モード) は全て有効。

引数で実行モードを切り替えられます (`$ARGUMENTS`):

- `audit` : `AGENTOPS_DREAM_PROMOTE=audit` で実メモリを変更せず提案オペを staging に書き出す
  (ロールアウト確認・dry-run に推奨)。
- それ以外/空 : `apply` (既定)。

実行コマンド (内容/パスは引数に補間せず、env でモード指定):

```sh
ROOT="${CLAUDE_PLUGIN_ROOT:?agentops plugin root unknown}"
LIB="$ROOT/scripts/dream-lib.sh"
WORKER="$ROOT/scripts/dream-worker.sh"

# shellcheck source=/dev/null
. "$LIB"

CWD="$(pwd)"
MEMDIR="$(AGENTOPS_DREAM_MEMORY_DIR="${AGENTOPS_DREAM_MEMORY_DIR:-}" sh -c 'echo "${AGENTOPS_DREAM_MEMORY_DIR}"')"
[ -n "$MEMDIR" ] || MEMDIR="$(memory_dir_from_cwd "$CWD")"
if [ ! -d "$MEMDIR" ]; then echo "no memory dir at $MEMDIR — nothing to refine"; exit 0; fi

STATE_DIR="$(state_dir_for "$MEMDIR")"
mkdir -p "$STATE_DIR"
CLAUDE_BIN="$(claude_bin)" || { echo "claude binary not found"; exit 0; }

# Mode: first arg 'audit' -> audit, else apply.
case "$ARGUMENTS" in *audit*) export AGENTOPS_DREAM_PROMOTE=audit ;; esac

# /dream bypasses the delta gate: FOCUS = the whole store. Write every id to the
# active delta file the worker re-reads under the lock (TOCTOU recheck).
LOCKDIR="$(lock_acquire "$MEMDIR")" || { echo "another dream is running (lock held)"; exit 0; }
trap 'lock_release "$LOCKDIR"; rm -f "$RT_DELTA"' EXIT
RT_DELTA="${STATE_DIR}/delta.active"
fingerprint "$MEMDIR" | awk -F'\t' '{print $1}' > "$RT_DELTA"

# Env var names MUST match what dream-worker.sh reads (see AGENTOPS_RT_* there).
export AGENTOPS_RT_MEMDIR="$MEMDIR" \
       AGENTOPS_RT_LOCKDIR="$LOCKDIR" \
       AGENTOPS_RT_DELTA="$RT_DELTA" \
       AGENTOPS_RT_STATE_DIR="$STATE_DIR" \
       AGENTOPS_RT_CWD="$CWD" \
       AGENTOPS_RT_CLAUDE_BIN="$CLAUDE_BIN" \
       AGENTOPS_RT_SESSION_ID="manual-dream" \
       CLAUDE_PLUGIN_ROOT="$ROOT"

# Run in the FOREGROUND (manual command), not detached.
"$WORKER"
echo "dream finished. log: ~/.claude/agentops/dream.log"
```

4. 完了後、`~/.claude/agentops/dream.log` の末尾サマリ (proposed / validated / applied 件数) を
   ユーザーに報告する。`audit` の場合は `~/.claude/agentops/staging/<key>/ops-*.json` の場所を
   案内する。

## 安全性メモ

- refinement-only: transcript を読まず、ストアに無い事実は導入しない。
- delete は高信頼 (>= max(threshold, 0.85)) のみ。下回れば flag に降格。
- 変更ファイルは `.bak` バックアップ + atomic 書き込みで可逆。
- マーカー外の AGENTS.md / MEMORY.md は決して書き換えない。
