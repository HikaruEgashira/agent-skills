---
name: import-agent-config
description: Codex と Claude Code の設定を dry-run import する
---

agent-config-import skill を使って、Codex と Claude Code の設定 import 計画を作ってください。

入力引数:

- `$ARGUMENTS`

要件:

- 指定がなければ dry-run のみ。
- `from claude` が含まれる場合は Claude Code -> Codex import。
- `from codex` が含まれる場合は Codex -> Claude Code import。
- 方向指定がなければ両方向の差分を調べて、source of truth 候補を提示する。
- secret/API key/token の値は出力しない。
- apply は `$ARGUMENTS` に `apply` が明示された場合だけ行う。
