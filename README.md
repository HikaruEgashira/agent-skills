### Hikae Marketplace

Personal Claude Code plugin marketplace for streamlined PR workflows and code quality management.

### Installation

```bash
claude plugin marketplace add HikaruEgashira/hikae-claude-code-marketplace
claude plugin install wf
claude plugin install architect
```

### Examples

#### Review an existing PR
```bash
/review <PR_URL>
```

#### Start from PR
```bash
/current
```

### Shell Function Shortcuts

Add these convenient shell functions to your `.zshrc` or `.bashrc` for quick access to common commands:

```bash
review() { claude "/review $1"; }
current() { claude "/current gh pr view | head -n 150 => $(gh pr view | head -n 150), gh pr diff | head -n 50 => $(gh pr diff | head -n 50) $1"; }
```
