### Hikae Marketplace

Personal Claude Code plugin marketplace for streamlined PR workflows and code quality management.

### Installation

```bash
/plugin marketplace add HikaruEgashira/hikae-claude-code-marketplace
/plugin install wf
```

### Usage Examples

#### Create a PR with code review
```bash
/pr
```

#### Review an existing PR
```bash
/review-pr <PR_URL>
```

#### Split changes into meaningful commits
```bash
/commit
```

#### Monitor PR until mergeable
```bash
/watch-pr <PR_URL>
```

### Shell Function Shortcuts

Add these convenient shell functions to your `.zshrc` or `.bashrc` for quick access to common commands:

```bash
watch() { claude "/watch-pr $1"; }
review() { claude "/review-pr $1"; }
current() { claude "/current-pr gh pr view | head -n 150 => $(gh pr view | head -n 150), gh pr diff | head -n 50 => $(gh pr diff | head -n 50) $1"; }
```

Usage:
```bash
# Watch current PR until it's mergeable
watch <PR_URL>

# Review a specific PR
review <PR_URL>

# Continue from current PR with context
current
```
