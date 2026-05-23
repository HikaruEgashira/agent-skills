`npx add-skill HikaruEgashira/agent-skills`

#### Skill Chain

| Skill | When to use | Behavior |
|-------|-------------| -------- |
| `worktree` | After Planning | Create Worktree |
| `commit-push-pr-flow` | After task completion | Create PR |
| `review-flow` | After PR creation | Review PR |
| `agent-config-import` | Codex/Claude Code 設定移行 | Import settings.json/config.toml, MCP, skills, prompts, commands |

#### Commands

| Command | Behavior |
|---------|----------|
| `/import-agent-config` | Dry-run Codex/Claude Code config import plan |

#### For Claude Code

```bash
claude plugin marketplace add HikaruEgashira/agent-skills
claude plugin install wf
claude plugin install interop
```

#### For Codex

Codex manifests are provided in each plugin directory under `.codex-plugin/plugin.json`.
The repo-local Codex marketplace is `.agents/plugins/marketplace.json`.

Installable Codex plugins:

- `wf`: workflow skills for worktree, commit, PR, and review flow
- `architect`: PR takeover and structure-refactoring skills converted from Claude commands
- `interop`: Codex / Claude Code configuration migration planning
- `meta`: risk assessment, incident handling, and gap-analysis skills

`sandbox-allowlist` includes Codex metadata, but it is not listed in the Codex marketplace because
Codex plugin validation does not accept hook declarations. It remains a Claude Code hook plugin.
