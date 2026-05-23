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
- auto mode / permission / approval / sandbox の仕様は変わりやすい。変換前に必ず公式 URL を確認し、確認した URL と日付を dry-run に書く。
- secret/API key/token の値は出力しない。環境変数名と参照方式だけ扱う。
- 既存設定を source of truth として尊重し、上書きではなく merge 案を出す。
- apply する場合は、対象ファイルごとに timestamp backup を作ってから編集する。
- permissions / sandbox / approval / hooks は等価ではない。雑に 1 フィールドへ潰さない。
- MCP は最優先で import する。多くの設定価値は MCP に集中している。
- hooks は移植不能または skill/plugin 化候補として扱い、暗黙に実行可能化しない。

## 最新仕様の確認 URL

変換ロジックを決める前に、必要な範囲だけ開いて確認する。特に permissions / auto mode / sandbox は記憶で判断しない。

### Codex

- Config reference: https://developers.openai.com/codex/config-reference
- Config basics: https://developers.openai.com/codex/config-basic
- Advanced config: https://developers.openai.com/codex/config-advanced
- Permissions: https://developers.openai.com/codex/permissions
- Agent approvals & security: https://developers.openai.com/codex/agent-approvals-security
- CLI command line options: https://developers.openai.com/codex/cli/reference
- MCP: https://developers.openai.com/codex/mcp
- Skills: https://developers.openai.com/codex/skills
- Plugins: https://developers.openai.com/codex/plugins
- Changelog: https://developers.openai.com/codex/changelog

### Claude Code

- Docs index: https://code.claude.com/docs/llms.txt
- Settings: https://code.claude.com/docs/en/settings
- Permissions: https://code.claude.com/docs/en/permissions
- Security: https://code.claude.com/docs/en/security
- Hooks reference: https://code.claude.com/docs/en/hooks
- CLI reference: https://code.claude.com/docs/en/cli-reference
- Plugins reference: https://code.claude.com/docs/en/plugins-reference
- Agent SDK permissions: https://code.claude.com/docs/en/agent-sdk/permissions
- What's new: https://code.claude.com/docs/en/whats-new

### Cross-tool references

- AGENTS.md spec: https://agents.md/
- Agent Skills: https://agentskills.io/
- skills.sh registry: https://skills.sh/
- Palot config converter reference implementation: https://github.com/ItsWendell/palot/tree/main/packages/configconv

## Permission / auto mode 方針

- Codex は approval と sandbox が分かれている前提で確認する。例: `approval_policy` と `sandbox_mode` は独立に扱い、UI 名の "Auto" / "Full Auto" だけで判断しない。
- Claude Code は permission mode と rules が混ざる。`default`, `plan`, `acceptEdits`, `bypassPermissions` の現在仕様を docs で確認する。
- Claude `acceptEdits` は Codex の「編集は許可、コマンドは確認」に近いが等価とは限らない。必ず推測として出す。
- Claude `bypassPermissions` と Codex の `approval_policy = "never"` / `sandbox_mode = "danger-full-access"` は同一視しない。sandbox の有無と network / writable roots を分けて評価する。
- `danger-full-access`, `bypassPermissions`, destructive command allow は apply しない。dry-run では強い警告と手動確認項目にする。
- Codex の granular approval / exec policy / runtime permission request が存在する場合は、現在の config reference を優先して mapping を更新する。

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

## Specs Checked

| Product | URL | Checked at | Notes |
|---------|-----|------------|-------|

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
