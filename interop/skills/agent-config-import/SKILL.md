---
name: agent-config-import
description: |
  Codex と Claude Code の設定を相互 import / migrate / sync したいときに使うスキルです。
  Claude Code の settings.json, .mcp.json, .claude/skills, commands, agents, hooks を Codex の config.toml, skills, prompts, AGENTS.md に反映する。
  Codex の config.toml, prompts, skills, AGENTS.md を Claude Code の settings.json, .mcp.json, .claude/skills, commands, agents, CLAUDE.md に反映する。
  Trigger: Codex Claude import, Claude Code Codex import, settings.json config.toml sync, agent config migration
---

## 目的

Codex と Claude Code の設定を、意味を壊さずに import する。
単純コピーではなく、変換可能・変換不能・手動判断が必要な項目を分ける。

## 原則

- 最初は必ず dry-run。ファイル編集前に差分、リスク、未対応項目を出す。
- secret/API key/token の値は出力しない。環境変数名と参照方式だけ扱う。
- 既存設定を source of truth として尊重し、上書きではなく merge 案を出す。
- apply する場合は、対象ファイルごとに timestamp backup を作ってから編集する。
- permissions / sandbox / approval / hooks は等価ではない。雑に 1 フィールドへ潰さない。
- MCP は最優先で import する。多くの設定価値は MCP に集中している。
- hooks は移植不能または skill/plugin 化候補として扱い、暗黙に実行可能化しない。

## 入力探索

### Claude Code 側

- `~/.claude/settings.json`
- `~/.claude/settings.local.json`
- `~/.claude.json`
- project `.claude/settings.json`
- project `.claude/settings.local.json`
- project `.mcp.json`
- `CLAUDE.md`
- `.claude/skills/**/SKILL.md`
- `.claude/commands/*.md`
- `.claude/agents/*.md`
- `.claude/hooks/**`

### Codex 側

- `~/.codex/config.toml`
- project `.codex/config.toml`
- `AGENTS.md`
- `~/.codex/skills/**/SKILL.md`
- project `.agents/skills/**/SKILL.md`
- `~/.codex/prompts/*.md`
- project `.codex/prompts/*.md`

存在しないファイルは skip として扱う。探索結果には、読んだパスと存在しなかった重要パスを短く記録する。

## Claude Code -> Codex import

### MCP

Claude:

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "env": { "TOKEN": "${TOKEN}" }
    }
  }
}
```

Codex:

```toml
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp@latest"]
env = { TOKEN = "${TOKEN}" }
```

Rules:

- `command`, `args`, `env`, `url` を維持する。
- embedded credential を含む URL は値を伏せ、手動確認に回す。
- disabled MCP は import しないか、コメント付き候補として扱う。

### model / env

- Claude `model` は Codex `model` に直訳せず、provider 差を確認する。
- Claude `env` は Codex `[shell_environment_policy].set` 候補にする。
- `ANTHROPIC_AUTH_TOKEN`, `OPENAI_API_KEY`, `AZURE_*` などの値は表示しない。

### permissions

- Claude `permissions.defaultMode` から Codex `approval_policy` / `sandbox_mode` を推測してよいが、必ず推測として明記する。
- `allow` / `deny` は Codex の直接設定にない場合、`AGENTS.md` または skill guidance への移植候補にする。
- destructive command allow は apply しない。手動確認に回す。

### hooks

- Claude hooks は Codex config に等価 import しない。
- 目的ごとに分類する。
  - formatter
  - guardrail
  - telemetry
  - context refresh
  - MCP/tool rewrite
- Codex で代替するなら skill, prompt, plugin, automation のどれに落とすかを提案する。

### skills / commands / agents

- `.claude/skills/**/SKILL.md` は `~/.codex/skills` または project `.agents/skills` へ copy/symlink 候補にする。
- `.claude/commands/*.md` は Codex `~/.codex/prompts/*.md` への変換候補にする。
- `.claude/agents/*.md` は Codex skill か AGENTS.md セクションへの変換候補にする。
- `CLAUDE.md` と `AGENTS.md` は、両方ある場合は diff を出す。片方だけなら canonical をどちらに置くか提案する。

## Codex -> Claude Code import

### MCP

Codex:

```toml
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp@latest"]
env = { TOKEN = "${TOKEN}" }
```

Claude:

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "env": { "TOKEN": "${TOKEN}" }
    }
  }
}
```

Rules:

- TOML parser を使える場合は使う。文字列置換だけで TOML を編集しない。
- `mcp_servers` は `.mcp.json` を優先出力先にする。user global に入れる必要がある場合だけ `~/.claude/settings.json` 候補にする。

### model / approval / sandbox

- Codex `model` は Claude `model` に直訳しない。Anthropic 互換モデルかどうかを確認する。
- Codex `approval_policy` / `sandbox_mode` は Claude `permissions.defaultMode` の候補にする。
- Codex command approval rules がある場合、Claude `permissions.allow` 候補にするが destructive command は手動確認に回す。

### prompts / skills

- Codex `~/.codex/prompts/*.md` は `.claude/commands/*.md` への変換候補にする。
- Codex `~/.codex/skills/**/SKILL.md` と `.agents/skills/**/SKILL.md` は `.claude/skills` への copy/symlink 候補にする。
- `AGENTS.md` は `CLAUDE.md` への symlink/copy 候補にする。両方が regular file なら上書きせず diff を出す。

## 出力フォーマット

Dry-run では必ずこの順番で出す。

````markdown
## Import Plan

Source:
Target:
Mode: dry-run

## Read Files

| Path | Status | Notes |
|------|--------|-------|

## Direct Imports

| Item | From | To | Action |
|------|------|----|--------|

## Needs Manual Review

| Item | Reason | Suggested handling |
|------|--------|--------------------|

## Not Portable

| Item | Reason |
|------|--------|

## Proposed Diff

```diff
...
```

## Apply Command

Apply only after the user asks for apply.
````

## Apply 手順

ユーザーが apply を明示した場合だけ実行する。

1. `git status --short` を確認する。
2. 対象ファイルごとに `.bak.<YYYYMMDDHHMMSS>` backup を作る。
3. structured parser で JSON/TOML を更新する。parser がない場合は patch を小さくする。
4. `git diff --check` を実行する。
5. 変更後の import summary を出す。

## 実装時の注意

- JSON は comments なしとして扱う。JSONC の可能性がある場合は parser を確認する。
- TOML は table order をできるだけ維持する。
- symlink は相対リンクを優先する。
- home 配下の編集はユーザーの明示 apply なしに行わない。
- repo 配下の project 設定を作る場合も backup と diff を出す。
