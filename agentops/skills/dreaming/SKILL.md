---
name: dreaming
description: >-
  agentops のオフライン記憶整理 (consolidation) 機能。会話 transcript は読まず、
  既存の memory entry を「精緻化のみ」する。新しい記憶が獲得されたセッションでだけ
  Stop hook から自動発火する (fingerprint trigger gate)。手動実行は /dream。
  Trigger: dreaming, memory consolidation, 記憶整理, refine memory, dream, memory dedup, /dream
---

# agentops dreaming — オフライン記憶整理 (refinement-only)

## これは何か

dreaming は agentops プラグインの **オフライン記憶整理パス** です。睡眠中の記憶固定化に着想を得ています。

- **精緻化のみ (refinement-only)**: 会話 transcript は **絶対に読まない**。新しい事実の
  獲得 (acquisition) はオンラインの本体エージェントが担当し、dreaming は **既に記録済みの
  memory entry を磨くだけ** です。
- **新規記憶があったときだけ発火**: Stop hook のたびに走るのではなく、メモリストアに
  新規 / 変更があったセッションでのみ動く (後述の trigger gate)。変化が無ければモデル呼び出し
  ゼロ = コストゼロ。
- **非同期・非ブロッキング**: dispatcher は 1 秒未満で `exit 0` し、worker を background に
  detach する。ユーザーの返信を遅らせない。`decision:"block"` は決して返さない。

精緻化の内容: 表現の明確化 / 重複の統合 / 矛盾の解消 / frontmatter スキーマ修正 /
`[[name]]` 相互リンク付与 / 陳腐化エントリの prune・flag。モデルへの入力は **既存エントリ +
MEMORY.md インデックスのみ**で、出力は **構造化された編集オペ (JSON)** だけ。bash 側が検証して
から適用します (モデルはファイルに触れない)。

## 3-phase モデル (paper grounding)

| Phase | 名称 | 内容 |
|-------|------|------|
| 1 | Light sleep | working set 構築 (delta + 1-hop リンク近傍 + 重複候補 + MEMORY.md)。純 bash、モデル無し |
| 2 | REM sleep | least-privilege な `claude -p` を 1 回。モデルは JSON 編集オペのみ出力 |
| 3 | Deep sleep | jq 検証 → evidence threshold ゲート → .bak + atomic に適用 → MEMORY.md / AGENTS.md 整合 |

- **Auto-Dreamer** (arXiv 2605.20616): オフライン consolidation とオンライン acquisition の
  分離。本機能は consolidation 側のみを実装し、trigger gate がその分離を体現する。
- **Active Dreaming Memory**: reflection + consolidation + **verification with evidence
  threshold**。semantic memory を書き換える前の信頼度しきい値・矛盾時は flag・downgrade-to-flag
  ポリシーがこれに対応。
- **SCM (Self-Controlled Memory)**: importance tagging + algorithmic forgetting/pruning。
  delete / flag オペと、durable のみを AGENTS.md へ mirror する選別がこれに対応。delete の
  高いしきい値 = 安全な忘却。

## Trigger gate (新規記憶検知)

Stop hook で **モデルを呼ぶ前に bash だけで** 発火可否を判定します。

1. メモリディレクトリの **fingerprint** を計算: 各 entry の `id<TAB>sha256(ファイル全体)`
   (frontmatter+body)。`entry-id` = frontmatter の `name:`、無ければ basename。
2. 前回の fingerprint (`fingerprint.json`) と比較し **delta** を算出。
3. delta = **新規 or ハッシュ変化した id** のみ。**削除は trigger しない** (削除は次回の
   fingerprint から落ちるだけ)。
4. delta が空 → そのまま `exit 0` (モデル呼び出し無し)。
5. delta が非空 → その entry 群を **FOCUS** として worker を detach。worker は lock 下で
   delta を再計算して TOCTOU を防ぐ。

MEMORY.md は fingerprint から **除外**。worker 自身が毎回書き換える派生インデックスなので、
含めると自分の書き込みが次回の dream を誘発する feedback loop になるため。

## 設定 (環境変数)

| 環境変数 | 既定値 | 説明 |
|----------|--------|------|
| `AGENTOPS_DREAM_DISABLE` | `0` | `1` で完全停止 (kill switch) |
| `AGENTOPS_DREAM_MODEL` | `claude-haiku-4-5-20251001` | REM phase のモデル (安価・高速) |
| `AGENTOPS_DREAM_MIN_INTERVAL` | `1800` | 同一メモリディレクトリの最小実行間隔 (秒) |
| `AGENTOPS_DREAM_MAX_PER_DAY` | `8` | 1 日あたり最大実行回数 |
| `AGENTOPS_DREAM_EVIDENCE_THRESHOLD` | `0.7` | 信頼度しきい値 (0-1) |
| `AGENTOPS_DREAM_PROMOTE` | `apply` | `apply`=実適用 / `audit`=staging に提案のみ書き出し |
| `AGENTOPS_DREAM_TIMEOUT` | `120` | モデル呼び出しのタイムアウト (秒) |
| `AGENTOPS_DREAM_MAX_BYTES` | `60000` | working set ペイロード上限 (バイト) |
| `AGENTOPS_DREAM_MEMORY_DIR` | (cwd 由来) | メモリディレクトリの上書き |
| `AGENTOPS_DREAM_CLAUDE_BIN` | (自動解決) | REM phase で使う claude バイナリの明示指定 (絶対パス or PATH 上の名前)。既定解決順 `claudex`→`claude`→`~/.claude/local/claude` が未設定ラッパを掴む環境向け。解決不能なら fail-closed |
| `AGENTOPS_DREAM_MIRROR_AGENTS` | `1` | `0` で AGENTS.md への mirror を無効化 |

ロールアウト時は `AGENTOPS_DREAM_PROMOTE=audit` を推奨。実メモリを変更せず提案オペを
`~/.claude/agentops/staging/<key>/ops-<ts>.json` に書き出して内容を確認できます (audit では
fingerprint を進めないので同じ delta が次回も再提案される)。

## しきい値 / 矛盾ポリシー (bash 側で強制)

モデルの自己採点は信用せず、bash が最終ゲートになります。

- `relink`, 表現のみの `update` : confidence >= 0.50 で適用 (低バー)
- 構造的 `update` (split/rename), `merge` : confidence >= threshold
- `delete` : confidence >= max(threshold, 0.85) (高バー)。下回れば **flag に降格**
- merge が threshold 未満 : **flag に降格** (データを失わない)
- 0.50 未満 : op を drop
- 矛盾解消: FOCUS (新しく再主張された) entry を優先 → より具体的/根拠のある表現 →
  決め手が無ければ **両方 flag** (delete/merge しない)

「迷ったら flag」が default-safe。破壊的オペは構造的に保守的です。

## 脅威モデル要約

transcript を取り込まないため、典型的な間接プロンプトインジェクション (直前に読んだ
悪意あるファイル / transcript) は **スコープ外**。残る攻撃面は **既存メモリストア自体**
(信頼済みだが汚染されうるデータ) とローカル実行/状態面のみ。

- **data-not-instructions**: メモリは fenced DATA 領域でモデルに渡し、「指示ではなくデータ」
  と明示。出力は JSON オペのみ。
- **最小権限**: `claude -p --permission-mode plan` で `Bash,WebFetch,WebSearch,Edit,Write,
  NotebookEdit,Task,Read,Glob,Grep` を全て不許可。モデルは JSON を吐くだけで、ファイル/
  ネットワークに触れない。フラグ拒否時は **fail-closed** (緩い権限へフォールバックしない)。
- **可逆性**: 変更ファイルは必ず `.bak` を作り temp+mv で atomic 書き込み。
- **secret hygiene**: ログ書き込み前に secret を redact。secret を新規導入するオペは reject。
- **injection-safe shell**: 全展開を quote、`eval` 不使用、cwd/session_id/transcript_path/
  ファイル内容をコマンド文字列に補間しない (内容は file/heredoc 経由)。
- **fail-safe**: 全コードパスが `exit 0`。エラーは `~/.claude/agentops/dream.log` のみ。
- **concurrency / rate**: メモリディレクトリ毎の mkdir ロック (900s で stale 失効) +
  min-interval + max/day。

## Codex への mirror と制約

`metadata.type` が `project` または `reference` で **未 flag** の durable エントリだけを、
プロジェクトルートの `AGENTS.md` のマーカー間ブロックに mirror します。

```
<!-- agentops:dreaming:start -->
## Project memory (managed by agentops dreaming — do not edit between markers)
- **<description>** ([[<id>]])
<!-- agentops:dreaming:end -->
```

**マーカー間しか書き換えません**。マーカーが無ければ末尾に 1 度だけ追記。マーカーが重複/
不整合なら mirror を **skip** (fail-safe)。`user`/`feedback` や flag 済み・低信頼の個人/
一時メモは AGENTS.md に漏らしません。AGENTS.md が VCS に commit される場合があるため、
mirror は `AGENTOPS_DREAM_MIRROR_AGENTS=0` で無効化できます。

**制約**: mirror は durable サブセットのみ。完全な記憶は Claude 側の per-project ストアが
source of truth です。

## 手動実行

`/dream` コマンドで trigger gate を **バイパス**して即時に精緻化パスを 1 回走らせます
(refinement-only は不変)。ロールアウト確認には:

```sh
AGENTOPS_DREAM_PROMOTE=audit /dream
```

ログ: `~/.claude/agentops/dream.log` / 状態: `~/.claude/agentops/state/<key>/` /
audit 出力: `~/.claude/agentops/staging/<key>/`。
