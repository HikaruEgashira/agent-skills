# agent-skills

`npx add-skill HikaruEgashira/agent-skills`

Personal Claude Code / Codex plugins for PR workflow, agent operations, and harness engineering.

## Plugins

| Plugin | What it does |
|--------|--------------|
| `wf` | Worktree → commit → PR → review-flow workflow skills |
| `architect` | Current-PR takeover and folder-structure refactoring |
| `agentops` | Import / migrate config between Codex and Claude Code |
| `meta` | Risk assessment, incident handling, gap analysis, the harness (agent-team factory), and the PMF audit harness |

### Skill Chain

| Skill | When to use | Behavior |
|-------|-------------| -------- |
| `worktree` | After Planning | Create Worktree |
| `commit-push-pr-flow` | After task completion | Create PR |
| `review-flow` | After PR creation | Review PR |
| `agent-config-import` | Codex/Claude Code 設定移行 | Import settings.json/config.toml, MCP, skills, prompts, commands |

### Commands

| Command | Behavior |
|---------|----------|
| `/import-agent-config` | Dry-run Codex/Claude Code config import plan |

## For Claude Code

```bash
claude plugin marketplace add HikaruEgashira/agent-skills
claude plugin install wf
claude plugin install architect
claude plugin install agentops
claude plugin install meta
```

## For Codex

Codex manifests are provided in each plugin directory under `.codex-plugin/plugin.json`.
The repo-local Codex marketplace is `.agents/plugins/marketplace.json`.

Installable Codex plugins:

- `wf`: workflow skills for worktree, commit, PR, and review flow
- `architect`: PR takeover and structure-refactoring skills converted from Claude commands
- `agentops`: Codex / Claude Code configuration migration planning
- `meta`: risk assessment, incident handling, gap analysis, the harness (agent-team factory), and the PMF audit harness

## License

Apache-2.0 — see [LICENSE](./LICENSE).
