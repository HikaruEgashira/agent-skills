---
name: harness
description: "Builds a harness: a meta-skill that defines specialist agents and generates the skills they use. Trigger when the user (1) asks to 'build/set up/construct a harness', (2) asks for 'harness design' or 'harness engineering', (3) wants a harness-based automation system for a new domain/project, (4) wants to restructure or extend an existing harness, or (5) asks to inspect, audit, sync, or maintain an existing harness (agents/skills drift, status check)."
---

# Harness — Agent Team & Skill Architect

A meta-skill that builds a harness for a domain or project: it defines each agent's role and generates the skills those agents use.

**Core principles:**
1. Generate agent definitions (`.claude/agents/`) and skills (`.claude/skills/`).
2. **Agent teams are the default execution mode.**
3. **Register a harness pointer in CLAUDE.md** — record only the trigger rule (pointer) so the orchestrator skill fires in new sessions. No change log in CLAUDE.md; the evolution log lives in the harness README.
4. **A harness is a living system, not a fixed artifact** — after every run, fold in feedback and keep agents, skills, and CLAUDE.md current.

## Workflow

### Phase 0: Status Audit

When the harness skill triggers, first establish what already exists.

1. Read `project/.claude/agents/`, `project/.claude/skills/`, and `project/CLAUDE.md`.
2. Branch on what you find:
   - **New build**: agent/skill directories absent or empty → run Phase 1 onward in full.
   - **Extend existing**: a harness exists and the user wants to add agents/skills → run only the phases the matrix below selects.
   - **Operate/maintain**: the user wants to audit, fix, or sync an existing harness → jump to the Phase 7-5 operate/maintain workflow.

   **Phase selection matrix (extending an existing harness):**
   | Change type | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 | Phase 6 |
   |----------|---------|---------|---------|---------|---------|---------|
   | Add agent | skip (reuse Phase 0 result) | placement only | required | if a dedicated skill is needed | edit orchestrator | required |
   | Add/edit skill | skip | skip | skip | required | if wiring changes | required |
   | Architecture change | skip | required | affected agents only | affected skills only | required | required |
3. Cross-check the existing agent/skill inventory against the README change log to detect drift.
4. Summarize the audit to the user and confirm the execution plan.

### Phase 1: Domain Analysis
1. Identify the domain/project from the request.
2. Identify the core task types (generation, validation, editing, analysis, etc.).
3. Using the Phase 0 audit, analyze conflicts/overlaps with existing agents and skills.
4. Explore the project codebase — tech stack, data models, key modules.
5. **Detect user proficiency** — read contextual cues (terminology used, depth of questions) to gauge technical level, then calibrate your communication tone. Don't use terms like "assertion" or "JSON schema" unexplained with users who show little coding experience.

### Phase 2: Team Architecture Design

#### 2-1. Choose the execution mode

**Agent teams are the top-priority default.** Whenever two or more agents collaborate, evaluate an agent team first. Teammates self-coordinate via direct messaging (SendMessage) and a shared task list (TaskCreate); sharing findings, debating conflicts, and covering each other's gaps raises output quality.

| Mode | When to use | Mechanism |
|------|----------|------|
| **Agent team** (default) | 2+ agents collaborating, real-time coordination/feedback, cross-referenced intermediate outputs | `TeamCreate` + `SendMessage` + `TaskCreate`, self-coordinating |
| **Subagent** (alternative) | Single-agent task, returning only a result to main is enough, team-comms overhead would be excessive | `Agent` tool called directly, parallel via `run_in_background` |
| **Hybrid** | Phases differ in character — e.g. parallel collection (sub) → consensus synthesis (team) | mix team/sub per phase |

**Decision order:**
1. First check whether an agent team works — for 2+ agents it's the default.
2. Pick subagents only when team communication is structurally unnecessary (result handoff only) and the team overhead outweighs its benefit.
3. If phases differ markedly, consider hybrid — name each phase's mode in the orchestrator.

> For the full comparison and per-pattern decision tree, see "Execution modes" in `references/agent-design-patterns.md`.

#### 2-2. Choose the architecture pattern

1. Decompose the work into areas of expertise.
2. Decide the team structure (patterns in `references/agent-design-patterns.md`):
   - **Pipeline**: sequential, dependent tasks
   - **Fan-out/Fan-in**: parallel, independent tasks
   - **Expert Pool**: context-dependent selective dispatch
   - **Producer-Reviewer**: generate, then quality-review
   - **Supervisor**: a central agent holds state and distributes work dynamically
   - **Hierarchical Delegation**: a higher agent delegates recursively to lower ones

#### 2-3. Agent separation criteria

Judge on four axes: expertise, parallelism, context, reusability. See "Agent separation criteria" in `references/agent-design-patterns.md`.

### Phase 3: Generate Agent Definitions

**Every agent must be defined as a file at `project/.claude/agents/{name}.md`.** Putting a role directly in an Agent tool's prompt without a definition file is prohibited, because:
- A file-based definition can be reused in later sessions.
- An explicit team communication protocol is what guarantees collaboration quality.
- The harness's core value is separating the agent (who) from the skill (how).

Create a definition file even when using a built-in type (`general-purpose`, `Explore`, `Plan`). Pass the built-in type via the Agent tool's `subagent_type` parameter; the definition file carries the role, principles, and protocol.

**Model:** every agent uses `model: "opus"`. Always pass `model: "opus"` on Agent calls. Harness quality is bound to agent reasoning, and opus gives the best quality.

**Team reconfiguration:** only one team can be active per session, but you may disband and form new teams between phases. When a Pipeline needs a different mix of specialists per phase, save the previous team's output to file, clear the team, and create a new one.

Define each agent in `project/.claude/agents/{name}.md`. Required sections: core role, working principles, input/output protocol, error handling, collaboration. In agent-team mode, add a `## Team Communication Protocol` section naming message senders/receivers and the scope of task requests.

> For the definition template and full example files, see "Agent definition structure" in `references/agent-design-patterns.md` plus `references/team-examples.md`.

**When including a QA agent:**
- Use the `general-purpose` type (`Explore` is read-only and can't run verification scripts).
- The point of QA is not "does it exist" but **cross-boundary comparison** — read the API response and the frontend hook together and compare their shapes.
- Run QA incrementally, right after each module completes — not once at the end.
- See `references/qa-agent-guide.md`.

### Phase 4: Generate Skills

Generate each agent's skills at `project/.claude/skills/{name}/SKILL.md`. See `references/skill-writing-guide.md` for the authoring guide.

#### 4-1. Skill structure

```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter (name, description required)
│   └── Markdown body
└── Bundled resources (optional)
    ├── scripts/    - executable code for repetitive/deterministic work
    ├── references/ - reference docs loaded on demand
    └── assets/     - files used in output (templates, images, etc.)
```

#### 4-2. Writing the description — trigger assertively

The description is a skill's only trigger mechanism. Claude tends to judge triggers conservatively, so write the description **assertively ("pushy")**.

**Bad:** `"A skill that processes PDF documents"`
**Good:** `"Read PDFs and perform every PDF operation — text/table extraction, merge, split, rotate, watermark, encrypt, OCR. Use this skill whenever a .pdf file is mentioned or a PDF deliverable is requested."`

Key: state both what the skill does and the concrete trigger situations, written so it's distinguishable from similar cases that should *not* trigger it.

#### 4-3. Body principles

| Principle | What it means |
|------|------|
| **Explain why** | Instead of coercive ALWAYS/NEVER, give the reason. An LLM that understands the reason judges edge cases correctly. |
| **Stay lean** | The context window is a shared resource. Target under 500 lines for the SKILL.md body; delete what doesn't earn its weight or move it to references/. |
| **Generalize** | Explain the principle so the skill handles varied input, rather than narrow rules fitted to one example. No overfitting. |
| **Bundle repeated code** | When agents keep writing the same script during test runs, bundle it ahead of time in `scripts/`. |
| **Write imperatively** | Use a directive, imperative voice. |

#### 4-4. Progressive Disclosure

Skills manage context with a three-stage loading system:

| Stage | Loaded when | Size target |
|------|----------|----------|
| **Metadata** (name + description) | always in context | ~100 words |
| **SKILL.md body** | on trigger | <500 lines |
| **references/** | only when needed | unlimited (scripts run without loading) |

**Size rules:**
- As SKILL.md approaches 500 lines, split detail into references/ and leave a pointer in the body saying when to read it.
- Reference files over 300 lines get a table of contents at the top.
- When there are domain/framework variants, split references/ by domain so only the relevant file loads.

```
cloud-deploy/
├── SKILL.md (workflow + selection guide)
└── references/
    ├── aws.md    ← loaded only when AWS is chosen
    ├── gcp.md
    └── azure.md
```

#### 4-5. Skill–agent wiring

- One agent ↔ one-to-many skills (1:1 or 1:N).
- A skill shared by several agents is fine.
- Skills hold "how"; agents hold "who".

> For authoring patterns, examples, and the data-schema standard, see `references/skill-writing-guide.md`.

### Phase 5: Integration & Orchestration

The orchestrator is a special skill that weaves individual agents and skills into one workflow and coordinates the whole team. Where the Phase 4 skills define "what each agent does and how," the orchestrator defines "who collaborates, when, in what order." See `references/orchestrator-template.md` for the template.

**Editing the orchestrator when extending:** when extending rather than building new, edit the existing orchestrator instead of creating one. Adding an agent means reflecting it in team composition, task assignment, and data flow, and adding its trigger keywords to the description.

The orchestrator pattern follows the execution mode chosen in Phase 2-1:

#### 5-0. Orchestrator patterns (by mode)

**Agent-team pattern (default):**
The orchestrator builds the team with `TeamCreate` and assigns work with `TaskCreate`. Teammates communicate directly via `SendMessage` and self-coordinate. The leader (orchestrator) monitors progress and synthesizes results.

```
[orchestrator/leader]
    ├── TeamCreate(team_name, members)
    ├── TaskCreate(tasks with dependencies)
    ├── teammates self-coordinate (SendMessage)
    ├── collect and synthesize results
    └── tear down the team
```

**Subagent pattern (alternative):**
The orchestrator calls subagents directly via the `Agent` tool. Parallelize with `run_in_background: true`; results return only to main. Use when team comms are unnecessary and you want less overhead.

```
[orchestrator]
    ├── Agent(agent-1, run_in_background=true)
    ├── Agent(agent-2, run_in_background=true)
    ├── await and collect results
    └── produce the integrated deliverable
```

**Hybrid pattern:**
Mix modes per phase. Common combinations:
- **Parallel collection (sub) → consensus synthesis (team)**: gather independent material with subagents in Phase 2 → form a team in Phase 3 to debate and synthesize.
- **Team draft (team) → verification (sub)**: a team drafts in Phase 2 → a single subagent verifies independently in Phase 3.
- **Reconfigure between phases**: `TeamDelete` then a new `TeamCreate` per phase, with subagent calls in between.

For hybrids, name each phase's mode at the top of its orchestrator section (e.g. `**Execution mode:** agent team`).

#### 5-1. Data-passing protocol

Specify in the orchestrator how data moves between agents:

| Strategy | Mechanism | Mode | Fits |
|------|------|----------|-----------|
| **Message-based** | direct teammate comms via `SendMessage` | team | real-time coordination, feedback, lightweight state |
| **Task-based** | shared task state via `TaskCreate`/`TaskUpdate` | team | progress tracking, dependencies, requesting work |
| **File-based** | write/read files at agreed paths | team + sub | large data, structured deliverables, audit trail |
| **Return-value** | the `Agent` tool's return message | sub | main collects subagent results directly |

**Recommended (team mode):** task-based (coordination) + file-based (deliverables) + message-based (real-time).
**Recommended (sub mode):** return-value (results) + file-based (large deliverables).
**Hybrid:** apply the combination matching each phase's mode.

File-based rules:
- Create a `_workspace/` folder under the working directory for intermediate output.
- Filename convention: `{phase}_{agent}_{artifact}.{ext}` (e.g. `01_analyst_requirements.md`).
- Output only the final deliverable to the user's path; keep intermediate files (`_workspace/`) for post-hoc verification and audit trail.

#### 5-2. Error handling

Include an error-handling policy in the orchestrator. Core rule: retry once, then proceed without that result if it fails again (note the gap in the report); never delete conflicting data — record both with their sources.

> For the per-error strategy table and implementation detail, see "Error handling" in `references/orchestrator-template.md`.

#### 5-3. Team-size guideline

| Work scale | Recommended members | Tasks per member |
|----------|------------|--------------|
| Small (5–10 tasks) | 2–3 | 3–5 |
| Medium (10–20 tasks) | 3–5 | 4–6 |
| Large (20+ tasks) | 5–7 | 4–5 |

> More members means more coordination overhead. Three focused members beat five scattered ones.

#### 5-4. Register the harness pointer in CLAUDE.md

After building the harness, register a minimal pointer in the project's `CLAUDE.md`. Since CLAUDE.md loads every session, recording only the harness's existence and trigger rule lets the orchestrator skill handle the rest.

**CLAUDE.md template:**

````markdown
## Harness: {domain}

**Goal:** {one line — the harness's core goal}

**Trigger:** for {domain} work, use the `{orchestrator-skill-name}` skill. Simple questions can be answered directly.
````

**What NOT to put in CLAUDE.md:** the agent list, skill list, directory structure, detailed execution rules, **or a change log**. Why: the agent/skill lists live in the orchestrator skill and under `.claude/agents/`, `.claude/skills/`, so duplicating them is waste; the directory structure is visible in the filesystem; and a change log is history noise in a file that loads every session. CLAUDE.md holds only the **pointer (trigger rule)**. The change log lives in the harness README (see Phase 7-3).

#### 5-5. Support follow-up work

The orchestrator must handle follow-ups, not just the first run. Guarantee three things:

**1. Follow-up keywords in the orchestrator description:**
Initial-build keywords alone won't trigger follow-up requests. Include expressions like:
- "run again", "re-run", "update", "fix", "extend"
- "redo just the {sub-task} of {domain}"
- "based on the previous result", "improve the output"

**2. A context-check step in the orchestrator's Phase 1:**
At workflow start, check for existing output to decide the run mode:
- `_workspace/` exists + user requests a partial fix → **partial re-run** (re-invoke only that agent)
- `_workspace/` exists + user provides new input → **new run** (move the old `_workspace` to `_workspace_prev/`)
- `_workspace/` absent → **initial run**

**3. Re-invocation guidance in agent definitions:**
State in each agent `.md` how to behave when prior output exists:
- if a prior result file exists, read it and fold in improvements
- if user feedback is given, change only that part

> See the "Phase 0: context check" section of `references/orchestrator-template.md`.

### Phase 6: Validation & Testing

Validate the generated harness. See `references/skill-testing-guide.md` for the methodology.

#### 6-1. Structure validation

- Confirm every agent file is in the right place.
- Validate skill frontmatter (name, description).
- Check cross-references between agents are consistent.
- Confirm no commands were generated.

#### 6-2. Mode-specific validation

- **Agent team**: check comms paths between members, task dependencies, and that team size is appropriate.
- **Subagent**: check each agent's I/O wiring, `run_in_background` settings, and return-value collection.
- **Hybrid**: confirm each phase's mode is named in the orchestrator and that data isn't dropped at phase boundaries (on team→sub, the team's output feeds the sub's input).

#### 6-3. Skill execution test

Run a real execution test on each generated skill:

1. **Write test prompts** — 2–3 realistic prompts per skill, phrased as a real user naturally would.

2. **With-skill vs without-skill** — where possible, run with and without the skill in parallel to confirm the skill's added value. Spawn two agents:
   - **With-skill**: read the skill, do the work.
   - **Without-skill (baseline)**: same prompt, no skill.

3. **Evaluate** — judge output quality qualitatively (user review) and quantitatively (assertion-based). When output is objectively verifiable (file created, data extracted), define assertions; when subjective (tone, design), rely on user feedback.

4. **Iterate** — when a test surfaces a problem:
   - **generalize** the feedback into a skill fix (no narrow one-example fixes)
   - re-test
   - repeat until the user is satisfied or improvement plateaus

5. **Bundle repeated patterns** — when agents keep writing the same code during tests (e.g. the same helper script every time), bundle it in `scripts/`.

#### 6-4. Trigger validation

Verify each skill's description triggers correctly:

1. **Should-trigger queries** (8–10) — varied expressions that should trigger the skill (formal/casual, explicit/implicit).
2. **Should-NOT-trigger queries** (8–10) — "near-miss" queries with similar keywords where a different tool/skill is the right fit.

**Writing near-misses:** an obviously unrelated query like "write a Fibonacci function" has no test value. A query on a fuzzy boundary — "extract the chart from this Excel file as PNG" (xlsx skill vs image conversion) — is a good test case.

Also check trigger collisions with existing skills here.

#### 6-5. Dry-run

- Review that the orchestrator's phase order is logical.
- Confirm the data-passing path has no dead links.
- Confirm every agent's input matches a prior phase's output.
- Confirm each error scenario's fallback path is executable.

#### 6-6. Write test scenarios

- Add a `## Test scenarios` section to the orchestrator skill.
- Describe at least one happy path and one error path.

### Phase 7: Harness Evolution

A harness isn't a static, build-once artifact — it's a system that keeps evolving with user feedback.

#### 7-1. Collect feedback after each run

After every harness run, ask the user for feedback:
- "Anything to improve in the result?"
- "Anything to change in the team or workflow?"

Skip if there's no feedback. Don't force it, but always offer the opening.

#### 7-2. Feedback routing

The fix target depends on the feedback type:

| Feedback type | Fix target | Example |
|-----------|----------|------|
| Output quality | that agent's skill | "analysis too shallow" → add depth criteria to the skill |
| Agent role | agent definition `.md` | "we also need security review" → add an agent |
| Workflow order | orchestrator skill | "verify first" → reorder phases |
| Team composition | orchestrator + agents | "these two could merge" → merge agents |
| Missing trigger | skill description | "doesn't fire on this phrasing" → extend the description |

#### 7-3. Change log

Record every change in a **change-log table in the harness README** (e.g. the plugin's `README.md`), not in CLAUDE.md — CLAUDE.md loads every session and should stay free of history noise. If the harness has no README, create one for this purpose or rely on git history.

```markdown
## Change log
| Date | Change | Target | Reason |
|------|----------|------|------|
| 2026-04-05 | initial build | all | - |
| 2026-04-07 | add QA agent | agents/qa.md | feedback: output quality unverified |
| 2026-04-10 | add tone guide | skills/content-creator | feedback: "too stiff" |
```

The log tracks how the harness evolved and guards against regression.

#### 7-4. Evolution triggers

Propose evolution not only on an explicit "fix the harness," but also when:
- the same kind of feedback recurs 2+ times
- an agent shows a repeated failure pattern
- the user is observed bypassing the orchestrator to work manually

#### 7-5. Operate/maintain workflow

Systematically inspect, fix, and sync an existing harness. Follow this when Phase 0 branched to "operate/maintain."

**Step 1: Status audit**
- Compare the `.claude/agents/` file list against the orchestrator's agent roster → list mismatches.
- Compare the `.claude/skills/` directory list against the orchestrator's skill roster → list mismatches.
- Report the audit to the user.

**Step 2: Incremental add/edit**
- Add/edit/remove agents and skills per the user's request.
- One change at a time; run Step 3 (sync) immediately after each.

**Step 3: Update the README change log**
- Record date, change, target, and reason in the harness README's change-log table (not CLAUDE.md).

**Step 4: Validate the change**
- Structure-validate the edited agents/skills (Phase 6-1).
- If the change affects triggers, trigger-validate (Phase 6-4).
- For large changes (architecture change, 3+ agents added/removed), also run Phase 6-3 (execution test) and 6-5 (dry-run).
- Finally confirm CLAUDE.md matches the actual files.

## Deliverable checklist

After generation, confirm:

- [ ] `project/.claude/agents/` — **agent definition files created** (required even for built-in types)
- [ ] `project/.claude/skills/` — skill files (SKILL.md + references/)
- [ ] one orchestrator skill (data flow + error handling + test scenarios)
- [ ] execution mode stated (agent team / subagent / hybrid; for hybrid, mode per phase)
- [ ] `model: "opus"` on every Agent call
- [ ] `.claude/commands/` — nothing generated
- [ ] no conflict with existing agents/skills
- [ ] skill descriptions written assertively ("pushy") — **including follow-up keywords**
- [ ] SKILL.md body under 500 lines; split to references/ if over
- [ ] execution verified with 2–3 test prompts
- [ ] trigger validation done (should-trigger + should-NOT-trigger)
- [ ] **harness pointer registered in CLAUDE.md** (trigger rule only — no change log)
- [ ] **agent/skill add/remove/edit recorded in the README change log** (not CLAUDE.md)
- [ ] **context-check step in orchestrator Phase 1** (initial / follow-up / partial re-run)

## References

- Harness patterns: `references/agent-design-patterns.md`
- Existing harness examples (with full files): `references/team-examples.md`
- Orchestrator template: `references/orchestrator-template.md`
- **Skill authoring guide**: `references/skill-writing-guide.md` — patterns, examples, data-schema standard
- **Skill testing guide**: `references/skill-testing-guide.md` — testing, evaluation, iteration methodology
- **QA agent guide**: `references/qa-agent-guide.md` — for including a QA agent in a build harness. Covers integration-consistency verification, cross-boundary bug patterns, and a QA agent definition template, based on 7 real-world bug cases.
