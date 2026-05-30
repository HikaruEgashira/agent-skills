# Orchestrator Skill Templates

An orchestrator is the higher-level skill that coordinates the whole team. There are three templates, one per execution mode:

- **Template A: Agent-team mode (default)** — the first choice whenever two or more agents collaborate
- **Template B: Subagent mode (alternative)** — when team communication isn't needed
- **Template C: Hybrid mode** — mix modes per phase

---

## Template A: Agent-Team Mode (Default · First Choice)

The **default mode to consider first** whenever two or more agents collaborate. Assemble the team with `TeamCreate` and coordinate through the shared task list and `SendMessage`.

```markdown
---
name: {domain}-orchestrator
description: "Orchestrator coordinating the {domain} agent team. {initial-run keywords}. Follow-up work: always use this skill when revising {domain} results, re-running parts, updating, supplementing, re-running, or improving prior results."
---

# {Domain} Orchestrator

The integrated skill that coordinates the {domain} agent team to produce {final deliverable}.

## Execution Mode: Agent Team

## Agent Lineup

| Teammate | Agent Type | Role | Skill | Output |
|------|-------------|------|------|------|
| {teammate-1} | {custom or built-in} | {role} | {skill} | {output-file} |
| {teammate-2} | {custom or built-in} | {role} | {skill} | {output-file} |
| ... | | | | |

## Workflow

### Phase 0: Context Check (follow-up support)

Check for existing deliverables to decide the execution mode:

1. Check whether the `_workspace/` directory exists
2. Decide the mode:
   - **No `_workspace/`** → initial run. Proceed to Phase 1
   - **`_workspace/` exists + user requests a partial revision** → partial re-run. Re-invoke only the relevant agents and overwrite only the deliverables being revised
   - **`_workspace/` exists + new input provided** → fresh run. Move the existing `_workspace/` to `_workspace_{YYYYMMDD_HHMMSS}/`, then proceed to Phase 1
3. On a partial re-run: include the prior deliverable paths in the agent prompts so each agent reads its prior result and folds in the feedback

### Phase 1: Setup
1. Analyze user input — {what you extract}
2. Create `_workspace/` in the working directory
   - **Initial run**: create a fresh `_workspace/`
   - **Fresh run**: move the existing `_workspace/` to `_workspace_{YYYYMMDD_HHMMSS}/`, then recreate `_workspace/`
3. Save input data to `_workspace/00_input/`

### Phase 2: Team Assembly

1. Create the team:
   ```
   TeamCreate(
     team_name: "{domain}-team",
     members: [
       { name: "{teammate-1}", agent_type: "{type}", model: "opus", prompt: "{role description and instructions}" },
       { name: "{teammate-2}", agent_type: "{type}", model: "opus", prompt: "{role description and instructions}" },
       ...
     ]
   )
   ```

2. Register tasks:
   ```
   TaskCreate(tasks: [
     { title: "{task 1}", description: "{detail}", assignee: "{teammate-1}" },
     { title: "{task 2}", description: "{detail}", assignee: "{teammate-2}" },
     { title: "{task 3}", description: "{detail}", depends_on: ["{task 1}"] },
     ...
   ])
   ```

   > 5–6 tasks per teammate is about right. Declare dependencies with `depends_on`.

### Phase 3: {main work — e.g. research/produce/analyze}

**How it runs:** teammates self-coordinate

Teammates claim tasks from the shared list and work independently.
The leader monitors progress and steps in when needed.

**Teammate communication rules:**
- {teammate-1} sends {what info} to {teammate-2} via SendMessage
- {teammate-2} saves its result to a file on completion and notifies the leader
- A teammate that needs another's result requests it via SendMessage

**Deliverable storage:**

| Teammate | Output Path |
|------|----------|
| {teammate-1} | `_workspace/{phase}_{teammate-1}_{artifact}.md` |
| {teammate-2} | `_workspace/{phase}_{teammate-2}_{artifact}.md` |

**Leader monitoring:**
- Receives automatic notifications when a teammate goes idle
- Steps in via SendMessage to unblock or reassign when a teammate stalls
- Checks overall progress with TaskGet

### Phase 4: {follow-up — e.g. verify/integrate}
1. Wait for all teammates to finish (check state with TaskGet)
2. Read each teammate's deliverable
3. {integration/verification logic}
4. Produce the final deliverable: `{output-path}/{filename}`

### Phase 5: Teardown
1. Ask teammates to shut down (SendMessage)
2. Delete the team (TeamDelete)
3. Keep the `_workspace/` directory (don't delete intermediate deliverables — they support post-hoc verification and audit trails)
4. Report a result summary to the user

> **When you need to reconfigure the team:** if different phases need different expert lineups, tear down the current team with TeamDelete, then build the next phase's team with a fresh TeamCreate. Deliverables in `_workspace/` survive, so the new team can Read them.

## Data Flow

```
[leader] → TeamCreate → [teammate-1] ←SendMessage→ [teammate-2]
                          │                           │
                          ↓                           ↓
                    artifact-1.md              artifact-2.md
                          │                           │
                          └───────── Read ────────────┘
                                     ↓
                              [leader: integrate]
                                     ↓
                              final deliverable
```

## Error Handling

| Situation | Strategy |
|------|------|
| One teammate fails/stops | leader detects → checks state via SendMessage → restarts or spawns a replacement |
| Majority of teammates fail | alert the user and confirm whether to continue |
| Timeout | use partial results gathered so far, shut down incomplete teammates |
| Conflicting data between teammates | keep both with sources attributed; never delete |
| Stale task state | leader checks with TaskGet, then updates manually with TaskUpdate |

## Test Scenarios

### Happy path
1. User provides {input}
2. Phase 1 derives {analysis result}
3. Phase 2 assembles the team ({N} teammates + {M} tasks)
4. Phase 3 runs with teammates self-coordinating
5. Phase 4 integrates deliverables into the final result
6. Phase 5 tears down the team
7. Expected: `{output-path}/{filename}` is created

### Error path
1. Phase 3: {teammate-2} stops on an error
2. Leader receives an idle notification
3. Checks state via SendMessage → attempts restart
4. If restart fails, reassigns {teammate-2}'s work to {teammate-1}
5. Proceeds to Phase 4 with the remaining results
6. Final report notes "part of {teammate-2}'s area not collected"
```

---

## Template B: Subagent Mode (Alternative)

For cases without team-communication overhead. Invoke agents directly with the `Agent` tool and collect results from their return values.

```markdown
---
name: {domain}-orchestrator
description: "Orchestrator coordinating {domain} agents. {initial-run keywords}. Include follow-up keywords."
---

## Execution Mode: Subagents

## Agent Lineup

| Agent | subagent_type | Role | Skill | Output |
|---------|--------------|------|------|------|
| {agent-1} | {built-in or custom} | {role} | {skill} | {output-file} |
| {agent-2} | ... | ... | ... | ... |

## Workflow

### Phase 0: Context Check
(Same as Template A — branch on whether `_workspace/` exists)

### Phase 1: Setup
1. Analyze input
2. Create `_workspace/` (on initial run, or right after moving the existing `_workspace/` to an archive directory on a fresh run)

### Phase 2: Parallel Execution
Invoke N Agent tools in a single message, concurrently:

| Agent | Input | Output | model | run_in_background |
|---------|------|------|-------|-------------------|
| {agent-1} | {source} | `_workspace/{phase}_{agent}_{artifact}.md` | opus | true |
| {agent-2} | {source} | `_workspace/{phase}_{agent}_{artifact}.md` | opus | true |

### Phase 3: Integration
1. Collect each agent's return value
2. Read file-based deliverables
3. Apply integration logic → final deliverable

### Phase 4: Teardown
1. Keep `_workspace/`
2. Report a result summary

## Error Handling
- One agent fails: retry once. If it fails again, note the gap and continue
- Majority fail: alert the user and confirm whether to continue
- Timeout: use partial results gathered so far
```

---

## Template C: Hybrid Mode

Use a different execution mode per phase. State `**Execution Mode:** {team | sub}` at the top of each phase.

```markdown
---
name: {domain}-orchestrator
description: "{domain} orchestrator (hybrid). {keywords}. Include follow-up keywords."
---

## Execution Mode: Hybrid

| Phase | Mode | Why |
|-------|------|------|
| Phase 2 (parallel collection) | subagents | independent collection, no team comms needed |
| Phase 3 (consensus integration) | agent team | conflicting data needs debate and consensus |
| Phase 4 (independent verification) | subagents | one QA agent verifies objectively |

## Workflow

### Phase 2: Parallel Collection
**Execution Mode:** subagents

Invoke N agents in parallel with the Agent tool in a single message (`run_in_background: true`).
Save each result to `_workspace/02_{agent}_raw.md`.

### Phase 3: Consensus-Based Integration
**Execution Mode:** agent team

1. Assemble the integration team with `TeamCreate` (editor + fact-checker + synthesizer)
2. Distribute work with `TaskCreate` — everyone Reads the Phase 2 `_workspace/02_*` files
3. Teammates discuss conflicting data via `SendMessage` and reach consensus on a file basis
4. Produce the final integration `_workspace/03_integrated.md`
5. Tear down the team with `TeamDelete`

### Phase 4: Independent Verification
**Execution Mode:** subagents

A single QA subagent takes `_workspace/03_integrated.md` as input and produces a verification report.
```

**Hybrid transition rules:**
- Team → sub: always tear the team down with `TeamDelete` before calling the Agent tool
- Sub → team: hand the subagents' file deliverables to teammates as Read paths
- Team → team: tear down the previous team before a new `TeamCreate` (only one team active per session)

---

## Authoring Principles

1. **State the execution mode first** — declare "Agent Team" / "Subagents" / "Hybrid" at the top of the orchestrator. Hybrid requires a per-phase mode table
2. **For team mode, be concrete about TeamCreate/SendMessage/TaskCreate usage** — assembly, task registration, communication rules
3. **For sub mode, fully specify the Agent tool parameters** — name, subagent_type, prompt, run_in_background, model
4. **Use absolute file paths** — no relative paths; clear paths rooted at `_workspace/`
5. **State inter-phase dependencies** — which phase depends on which phase's results. For hybrid, highlight the mode-transition points especially
6. **Be realistic about error handling** — don't assume everything succeeds
7. **Test scenarios are mandatory** — at least one happy path + one error path

## Follow-Up Keywords in the description

Initial-run keywords alone won't cut it for an orchestrator's description. Always include follow-up expressions like:

- re-run / run again / update / revise / supplement
- "just the {part} of {domain} again"
- "based on the prior result", "improve the result"
- everyday domain-related requests (e.g. for a launch-strategy Harness: "launch", "promo", "trending")

Without follow-up keywords, the Harness becomes effectively dead code after its first run.

## Reference Orchestrator

Baseline structure of a fan-out/fan-in orchestrator:
setup → Phase 0 (context check) → TeamCreate + TaskCreate → N teammates run in parallel → Read + integrate → teardown.
See the research-team example in `references/team-examples.md`.
