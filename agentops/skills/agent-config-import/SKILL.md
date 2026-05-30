---
name: agent-config-import
description: |
  Codex と Claude Code の設定を相互 import / migrate / sync する。
  settings.json / .mcp.json / skills / commands / agents / hooks / CLAUDE.md ⇄ config.toml / skills / prompts / AGENTS.md。
  分析と proposed diff は常に双方向 1 パスで出す。片方向 apply 依頼でも両方向を分析してから対象を絞る。
  Trigger: Codex Claude import, Claude Code Codex import, settings.json config.toml sync, agent config migration
---

## 目的

設定を意味を壊さず移送する。単純コピーせず、移送可能 / 手動判断 / 移送不能を分ける。

## 原則

- 最初は dry-run。編集前に差分・リスク・未対応項目を出す。
- 分析は双方向 1 パス。両方向の Direct / Manual / Not portable / Proposed diff を最初から出し、逆方向を問い返させない。
- permission / sandbox / approval / hooks は記憶で判断しない。編集前に公式 URL を開き、確認した URL と日付を残す。
- secret / token の値は出さない。環境変数名と参照方式だけ扱う。
- 既存設定が source of truth。上書きでなく merge 案を出す。
- apply は対象ごとに `.bak.<timestamp>` を取ってから。home 配下は明示 apply なしに触らない。
- 共有 symlink ストア（例 `~/.agents/skills/` を両ツールから相対 symlink）経由なら、import は symlink 作成に過ぎず有無は curation。gap と誤報しない。判断前に symlink / inode を実測する。
- nix 等で管理された symlink は store が read-only。canonical source を編集対象にし、deployed copy の再 sync は別ステップにする。
- MCP は最優先。設定価値が集中する。

## 仕様確認 URL

permission / sandbox / auto mode は特に記憶で判断しない。`<name>` を差し替えて必要分だけ開く。

- Codex `https://developers.openai.com/codex/<name>`: config-reference, permissions, mcp, skills, plugins, changelog
- Claude `https://code.claude.com/docs/en/<name>`: settings, permissions, hooks, plugins-reference, whats-new
- Cross: https://agents.md/ , https://agentskills.io/

## 入力探索

存在しないものは skip。読んだパスと欠落した重要パスを記録する。

- Claude: `~/.claude/settings.json`, `settings.local.json`, `~/.claude.json`(mcpServers), project `.claude/settings*.json`, `.mcp.json`, `CLAUDE.md`, `.claude/{skills,commands,agents,hooks}/**`
- Codex: `~/.codex/config.toml`, project `.codex/config.toml`, `AGENTS.md`, `~/.codex/skills/**`, project `.agents/skills/**`, `~/.codex/prompts/*.md`

## 変換マッピング（双方向対称）

| 領域 | Claude Code | Codex | 注意 |
|---|---|---|---|
| MCP | `mcpServers`{} (`.mcp.json` 優先 / settings) | `[mcp_servers.x]` (config.toml) | command/args/env/url を維持。TOML は parser で編集。embedded credential URL は伏せて手動。 |
| model | `model` | `model` | 直訳せず provider 互換を確認。 |
| env | `env`{} | `[shell_environment_policy.set]` | secret は名前と参照のみ。 |
| approval / sandbox | `permissions.defaultMode` | `approval_policy` + `sandbox_mode` | 1:1 でない。必ず推測明記。下記方針参照。 |
| allow / deny | `permissions.allow/deny` | granular approval / AGENTS.md guidance | 直接等価なし。destructive は手動。 |
| hooks | `.claude/hooks` + settings `hooks` | `hooks.json` / config | 等価移送しない。formatter/guardrail/telemetry/context/rewrite に分類し skill・prompt・plugin 化を提案。暗黙に実行可能化しない。 |
| skills | `.claude/skills/**` | `~/.codex/skills/**`, `.agents/skills/**` | copy/symlink。相対 symlink 優先。共有ストアなら symlink 1 本で済む。 |
| commands / prompts | `.claude/commands/*.md` | `~/.codex/prompts/*.md` | 相互変換候補。 |
| agents | `.claude/agents/*.md` | skill または AGENTS.md セクション | |
| memory | `CLAUDE.md` | `AGENTS.md` | 両方 regular file なら上書きせず diff。tool 固有記述(system prompt 参照等)は翻案か除外。片方のみなら canonical 配置を提案。 |

destructive allow / `danger-full-access` / `bypassPermissions` は apply せず、dry-run で警告と手動確認に回す。

## Permission / sandbox 方針

- Codex は approval と sandbox が独立。UI 名 "Auto"/"Full Auto" で判断しない。`approval_policy`(untrusted / on-request / never / granular) と `sandbox_mode`(read-only / workspace-write / danger-full-access) を分けて評価する。
- Claude `defaultMode`(default / acceptEdits / plan / auto / dontAsk / bypassPermissions) は現行仕様を docs で確認（`auto` は user scope のみ有効など制約あり）。
- 対応は推測として出す。`acceptEdits` ≈「編集許可・コマンド確認」、`bypassPermissions` ≠ `never`+`danger-full-access`。sandbox 有無と network / writable roots を分離して評価する。

## 出力フォーマット

双方向 1 パス。共有前置き(Specs / Read Files / Structural Findings)を 1 回、Direction A/B を各 1 ブロック、最後に統合 Apply を出す。各方向は 0 件でも「該当なし」と明記し省略しない。

````markdown
## Import Plan (Bidirectional) — Mode: dry-run

## Specs Checked
| Product | URL | Checked at | Notes |

## Read Files
| Path | Status | Notes |

## Structural Findings
共有ストア / symlink / nix 管理 / 既存 AGENTS.md・CLAUDE.md の drift / MCP 有無。symlink と inode は実測。

## Direction A — Codex → Claude Code
### Direct Imports
| Item | From | To | Action |
### Needs Manual Review
| Item | Reason | Suggested handling |
### Not Portable
| Item | Reason |
### Proposed Diff
```diff
# <target file>
```

## Direction B — Claude Code → Codex
（同じ 4 小節: Direct Imports / Needs Manual Review / Not Portable / Proposed Diff）

## Apply Command
両方向の候補を 1 リストに列挙し、方向・項目単位で選べるよう提示。Apply only after the user asks.
````

## Apply 手順

apply を明示されたときのみ。

1. `git status --short` を確認。dirty なら worktree で隔離。
2. 対象ごとに `.bak.<YYYYMMDDHHMMSS>`。
3. JSON / TOML は structured parser で更新（JSON は JSONC 可能性を確認、TOML は table order 維持）。
4. `git diff --check`。
5. canonical を編集した場合、deployed copy / 共有ストアを sync。
6. 変更後の import summary を出す。
