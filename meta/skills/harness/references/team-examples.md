# Agent Team Examples

---

## Example 1: Research Team (Agent-Team Mode)

### Team Architecture: Fan-out/Fan-in
### Execution Mode: Agent Team

```
[leader/orchestrator]
    ├── TeamCreate(research-team)
    ├── TaskCreate(4 research tasks)
    ├── teammates self-coordinate (SendMessage)
    ├── collect results (Read)
    └── produce synthesis report
```

### Agent Lineup

| Teammate | Agent Type | Role | Output |
|------|-------------|------|------|
| official-researcher | general-purpose | official docs/blogs | research_official.md |
| media-researcher | general-purpose | media/investment | research_media.md |
| community-researcher | general-purpose | community/social | research_community.md |
| background-researcher | general-purpose | background/competitive/academic | research_background.md |
| (leader = orchestrator) | — | synthesis report | synthesis_report.md |

> Researchers use the `general-purpose` built-in type but are still defined as `.claude/agents/{name}.md` files. Each file states the role, research scope, and Team Communication Protocol to guarantee reuse and collaboration quality.

### Orchestrator Workflow (Agent Team)

```
Phase 1: Setup
  - Analyze user input (topic, research mode)
  - Create _workspace/

Phase 2: Team Assembly
  - TeamCreate(team_name: "research-team", members: [
      { name: "official", prompt: "Investigate official channels..." },
      { name: "media", prompt: "Investigate media/investment trends..." },
      { name: "community", prompt: "Investigate community reactions..." },
      { name: "background", prompt: "Investigate background/competitive landscape..." }
    ])
  - TaskCreate(tasks: [
      { title: "Investigate official channels", assignee: "official" },
      { title: "Investigate media trends", assignee: "media" },
      { title: "Investigate community reactions", assignee: "community" },
      { title: "Investigate background landscape", assignee: "background" }
    ])

Phase 3: Research
  - 4 teammates research independently
  - Share interesting findings between teammates via SendMessage
    (e.g. media passes investment news to background)
  - On conflicting info, teammates debate directly
  - Each teammate saves a file on completion and notifies the leader

Phase 4: Integration
  - Leader Reads the 4 deliverables
  - Produces the synthesis report
  - Attributes sources for conflicting info

Phase 5: Teardown
  - Ask teammates to shut down
  - Tear down the team
  - Keep _workspace/ (for post-hoc verification and audit trails)
```

### Team Communication Pattern

```
official ──SendMessage──→ background  (share related official announcements)
media ────SendMessage──→ background  (share investment/acquisition info)
community ─SendMessage──→ media      (community reactions tied to media)
all teammates ──TaskUpdate──→ shared task list  (progress updates)
leader ←───── idle notification ──── finished teammate   (automatic)
```

---

## Example 2: Sci-Fi Novel Writing Team (Agent-Team Mode)

### Team Architecture: Pipeline + Fan-out
### Execution Mode: Agent Team

```
Phase 1 (parallel — agent team): worldbuilder + character-designer + plot-architect
  → coordinate consistency via SendMessage
Phase 2 (sequential): prose-stylist (drafting)
Phase 3 (parallel — agent team): science-consultant + continuity-manager (review)
  → share findings via SendMessage
Phase 4 (sequential): prose-stylist (revise per review)
```

### Agent Lineup

| Teammate | Agent Type | Role | Skill |
|------|-------------|------|------|
| worldbuilder | custom | worldbuilding | world-setting |
| character-designer | custom | character design | character-profile |
| plot-architect | custom | plot structure | outline |
| prose-stylist | custom | prose editing + drafting | write-scene, review-chapter |
| science-consultant | custom | science verification | science-check |
| continuity-manager | custom | consistency verification | consistency-check |

### Full Agent File Example: `worldbuilder.md`

```markdown
---
name: worldbuilder
description: "Expert who builds the world of a sci-fi novel. Designs physical laws, social structures, tech level, and history."
---

# Worldbuilder — Sci-Fi Worldbuilding Expert

You are a worldbuilding expert for sci-fi novels. Grounded in scientific fact yet pushing imagination further, you build the physical, social, and technological foundations of the world the story unfolds in.

## Core Responsibilities
1. Define the world's physical laws and tech level
2. Design social structures, political systems, and economies
3. Establish historical context and current conflicts
4. Describe the environment and atmosphere of each location

## Working Principles
- Internal consistency above all — no contradictions between settings
- Chain "what if this tech existed?" questions to infer the world's ripple effects
- The world serves the story — avoid over-detailed settings that obstruct the plot

## Input/Output Protocol
- Input: the user's world concept, genre requirements
- Output: `_workspace/01_worldbuilder_setting.md`
- Format: markdown, sectioned (physics/society/tech/history/places)

## Team Communication Protocol
- To character-designer: SendMessage social structure, class system, and occupational info
- To plot-architect: SendMessage the world's main conflicts and crisis elements
- From science-consultant: receive scientific-error feedback → revise settings
- Broadcast to all relevant teammates when the world changes

## Error Handling
- If the concept is ambiguous, propose 3 directions and ask the user to pick
- When you find a scientific error, propose an alternative alongside it

## Collaboration
- Provide social-structure info to character-designer
- Provide conflict-structure info to plot-architect
- Revise settings per science-consultant's feedback
```

### Detailed Team Workflow

```
Phase 1: TeamCreate(team_name: "novel-team", members: [worldbuilder, character-designer, plot-architect])
         TaskCreate([worldbuilding, character design, plot structure])
         → teammates self-coordinate, working in parallel
         → worldbuilder SendMessages character-designer when the social structure is done
         → character-designer SendMessages plot-architect when the protagonist is set

Phase 2: Tear down the Phase 1 team → invoke prose-stylist as a subagent (solo drafting needs no team)
         prose-stylist Reads the 3 deliverables in _workspace/ and drafts
         → saves the result to _workspace/02_prose_draft.md

Phase 3: Create a new team — TeamCreate(team_name: "review-team", members: [science-consultant, continuity-manager])
         (one team active per session, but the Phase 1 team is gone, so a new team is fine)
         → the two reviewers examine the draft and share findings
         → science-consultant alerts continuity-manager when it finds a physics error
         → tear down the team after review

Phase 4: Invoke prose-stylist as a subagent to make the final revisions per the review
```

---

## Example 3: Webtoon Production Team (Subagent Mode)

### Team Architecture: Producer-Reviewer
### Execution Mode: Subagents

> With only two agents in a Producer-Reviewer pattern, and result-passing mattering more than communication, subagents fit.

```
Phase 1: Agent(webtoon-artist) → generate panels
Phase 2: Agent(webtoon-reviewer) → inspect
Phase 3: Agent(webtoon-artist) → regenerate flagged panels (max 2 times)
```

### Agent Lineup

| Agent | subagent_type | Role | Skill |
|---------|--------------|------|------|
| webtoon-artist | custom | generate panel images | generate-webtoon |
| webtoon-reviewer | custom | quality inspection | review-webtoon, fix-webtoon-panel |

### Full Agent File Example: `webtoon-reviewer.md`

```markdown
---
name: webtoon-reviewer
description: "Expert who inspects webtoon panel quality. Evaluates composition, character consistency, text legibility, and direction."
---

# Webtoon Reviewer — Webtoon Quality Inspection Expert

You are an expert who inspects webtoon panel quality. You evaluate panels by visual polish, story delivery, and character consistency.

## Core Responsibilities
1. Evaluate each panel's composition and visual polish
2. Verify character appearance consistency across panels
3. Evaluate speech-bubble text legibility and placement
4. Review the episode's overall flow and pacing

## Working Principles
- Judge clearly on a 3-tier scale: PASS/FIX/REDO
- FIX = solvable with a partial edit; REDO = needs full regeneration
- Judge by objective criteria (consistency, legibility, composition), not subjective taste

## Input/Output Protocol
- Input: panel images in the `_workspace/panels/` directory
- Output: `_workspace/review_report.md`
- Format:
  ```
  ## Panel {N}
  - Verdict: PASS | FIX | REDO
  - Reason: [specific reason]
  - Fix instructions: [concrete direction if FIX/REDO]
  ```

## Error Handling
- If an image fails to load, mark that panel REDO
- A panel still REDO after 2 regenerations is passed with a warning

## Collaboration
- Hand fix instructions to webtoon-artist (file-based)
- Re-inspect regenerated panels (max 2-loop)
```

### Error Handling

```
Retry policy:
- REDO panel → ask artist to regenerate (with concrete fix instructions)
- Force PASS after a max 2-loop
- If 50%+ of all panels are REDO, propose a prompt revision to the user
```

---

## Example 4: Code Review Team (Agent-Team Mode)

### Team Architecture: Fan-out/Fan-in + Debate
### Execution Mode: Agent Team

> Code review is a showcase for agent teams. Reviewers with different angles share and challenge findings, enabling a deeper review.

```
[leader] → TeamCreate(review-team)
    ├── security-reviewer: check security vulnerabilities
    ├── performance-reviewer: analyze performance impact
    └── test-reviewer: verify test coverage
    → reviewers share findings (SendMessage)
    → leader synthesizes results
```

### Team Communication Pattern

```
security ──SendMessage──→ performance  ("this SQL query is injectable, check the perf angle too")
performance ──SendMessage──→ test      ("found an N+1 query, please check if a test covers it")
test ────SendMessage──→ security      ("no auth-module tests; your priority view from a security angle?")
```

The key: reviewers talk directly **without routing through the leader**, catching cross-domain issues fast.

---

## Example 5: Supervisor Pattern — Code Migration Team (Agent-Team Mode)

### Team Architecture: Supervisor
### Execution Mode: Agent Team

```
[supervisor/leader] → analyze file list → assign batches
    ├→ [migrator-1] (batch A)
    ├→ [migrator-2] (batch B)
    └→ [migrator-3] (batch C)
    ← receive TaskUpdate → assign more batches or reassign
```

### Agent Lineup

| Teammate | Role |
|------|------|
| (leader = migration-supervisor) | analyze files, distribute batches, manage progress |
| migrator-1~3 | migrate assigned file batches |

### Supervisor's Dynamic Distribution Logic (Agent-Team Use)

```
1. Collect the full list of target files
2. Estimate complexity (file size, import count, dependencies)
3. Register file batches as tasks with TaskCreate (with dependencies)
4. Teammates claim work themselves
5. When a teammate reports completion via TaskUpdate:
   - success → auto-claim the next task
   - failure → leader checks the cause via SendMessage → reassign or hand to another teammate
6. All tasks done → leader runs integration tests
```

Vs. fan-out: work is **assigned dynamically at runtime**, not fixed up front. The shared task list's self-claim feature maps naturally onto the supervisor pattern.

---

## Deliverable Pattern Summary

### Agent Definition File
Location: `project/.claude/agents/{agent-name}.md`
Required sections: Core Responsibilities, Working Principles, Input/Output Protocol, Error Handling, Collaboration
Team-mode extra section: **Team Communication Protocol** (message receive/send, task-claim scope)

### Skill File Structure
Location: `project/.claude/skills/{skill-name}/SKILL.md` (project level)
Or: `~/.claude/skills/{skill-name}/SKILL.md` (global level)

### Integrated Skill (Orchestrator)
The higher-level skill that coordinates the whole team. Defines the agent lineup and workflow per scenario.
Template: see `references/orchestrator-template.md`.
**Always state the execution mode** — agent team (default) or subagents.
