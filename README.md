`npx add-skill HikaruEgashira/agent-skills`

#### Skill Chain

| Skill | When to use | Behavior |
|-------|-------------| -------- |
| `worktree` | After Planning | Create Worktree |
| `commit-push-pr-flow` | After task completion | Create PR |
| `review-flow` | After PR creation | Review PR |

#### For Claude Code

```bash
claude plugin marketplace add HikaruEgashira/agent-skills
claude plugin install wf
```
