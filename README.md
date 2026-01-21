### Agent Skills Plugins

#### Installation

- All Coding Agent

```bash
npx add-skill HikaruEgashira/agent-skills
```

- For Claude Code

```bash
claude plugin marketplace add HikaruEgashira/agent-skills
claude plugin install wf
```

#### Skill Chain

| Skill | When to use | Behavior |
|-------|-------------| -------- |
| `assign` | When context is missing | Load context from PR |
| `commit-push-pr-flow` | After task completion | Create PR |
| `review-flow` | After PR creation | Review PR |

#### Validation

```bash
uv run --with pyyaml scripts/validate_skills.py
```
