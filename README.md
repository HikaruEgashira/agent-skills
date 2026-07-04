# agent-skills

`npx add-skill HikaruEgashira/agent-skills`

Personal Claude Code / Codex plugins for PR workflow, agent operations, and harness engineering.

## Plugins

| Plugin | What it does |
|--------|--------------|
| `wf` | Worktree → commit → PR → review-flow workflow skills |
| `architect` | Current-PR takeover and folder-structure refactoring |
| `agentops` | Import / migrate config between Codex and Claude Code · `dreaming` offline memory refinement |
| `meta` | Risk assessment, incident handling, gap analysis, the harness (agent-team factory), the PMF audit harness, and the falsehood audit for AI-generated code |

### Skill Chain

| Skill | When to use | Behavior |
|-------|-------------| -------- |
| `worktree` | After Planning | Create Worktree |
| `commit-push-pr-flow` | After task completion | Create PR |
| `review-flow` | After PR creation | Review PR |
| `agent-config-import` | Codex/Claude Code 設定移行 | Import settings.json/config.toml, MCP, skills, prompts, commands |
| `dreaming` | Stop hook 後（新規 memory 獲得時のみ自動） | 既存 memory を refine（重複統合・矛盾解消・剪定）。transcript は読まず新規獲得もしない。Claude memory を source、Codex `AGENTS.md` に mirror |

### Commands

| Command | Behavior |
|---------|----------|
| `/import-agent-config` | Dry-run Codex/Claude Code config import plan |
| `/dream` | Run a memory-refinement pass on demand (bypasses the new-memory gate, still refinement-only) |

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
- `meta`: risk assessment, incident handling, gap analysis, the harness (agent-team factory), the PMF audit harness, and the falsehood audit for AI-generated code

## License

Apache-2.0 — see [LICENSE](./LICENSE).
