# Agent Team Design Patterns

## Execution Modes: Agent Teams vs Subagents

Understand the core difference between the two execution modes and pick the one that fits.

### Agent Teams — Default Mode

A team leader assembles the team with `TeamCreate`, and each teammate runs as an independent Claude Code instance. Teammates talk directly via `SendMessage` and self-coordinate through a shared task list (`TaskCreate`/`TaskUpdate`).

```
[leader] ←→ [teammate A] ←→ [teammate B]
   ↕              ↕              ↕
   └────── shared task list ─────┘
```

**Core tools:**
- `TeamCreate`: create the team and spawn teammates
- `SendMessage({to: name})`: message a specific teammate
- `SendMessage({to: "all"})`: broadcast (expensive, use rarely)
- `TaskCreate`/`TaskUpdate`: manage the shared task list

**What it gives you:**
- Teammates converse, challenge, and verify each other directly
- Information flows between teammates without routing through the leader
- Self-coordination via the shared task list (teammates can claim their own work)
- Idle teammates notify the leader automatically
- Plan-approval mode lets you review risky actions before they run

**Constraints:**
- Only one team is **active** per session (but you can disband a team between phases and form a new one)
- No nested teams (a teammate cannot create its own team)
- The leader is fixed (cannot be transferred)
- Higher token cost

**Team-reconfiguration pattern:**
When different phases need different expert lineups, persist the previous team's deliverables to files, tear the team down, then create a new one. Deliverables left in `_workspace/` stay readable by the next team via Read.

### Subagents — Lightweight Mode

The main agent spawns subagents with the `Agent` tool. Subagents return their results only to the main agent and never talk to each other.

```
[main] → [sub A] → returns result
       → [sub B] → returns result
       → [sub C] → returns result
```

**Core tool:**
- `Agent(prompt, subagent_type, run_in_background)`: spawn a subagent

**What it gives you:**
- Light and fast
- Results summarized back into the main context
- Token-efficient

**Constraints:**
- No subagent-to-subagent communication
- The main agent owns all coordination
- No real-time collaboration or challenge

### Mode-Selection Decision Tree

```
Two or more agents?
├── Yes → Do the agents need to communicate?
│         ├── Yes → Agent team (default)
│         │         Cross-checking, shared discoveries, and live feedback raise quality.
│         │
│         └── No → Subagents work too
│                  Producer-Reviewer, Expert Pool, etc. — anything that only passes results back.
│
└── No (one) → Subagent
              A single agent needs no team.
```

> **Core principle:** Agent teams are the default. Before choosing subagents, ask: "Is teammate-to-teammate communication genuinely unnecessary here?"

---

## Agent Team Architecture Types

### 1. Pipeline
Sequential work. Each agent's output is the next agent's input.

```
[analyze] → [design] → [implement] → [verify]
```

**Fits when:** each stage depends heavily on the previous stage's deliverable
**Example:** novel writing — worldbuilding → characters → plot → drafting → editing
**Watch out:** a bottleneck stalls the whole pipeline. Design each stage to be as independent as possible.
**Team-mode fit:** strong sequential dependency limits the team-mode payoff. Useful only when the pipeline contains parallel stretches.

### 2. Fan-out/Fan-in
Parallel work, then merge. Independent tasks run concurrently.

```
         ┌→ [expert A] ─┐
[split] → ├→ [expert B] ─┼→ [merge]
         └→ [expert C] ─┘
```

**Fits when:** the same input needs analysis from different angles or domains
**Example:** comprehensive research — official/media/community/background investigated at once → unified report
**Watch out:** the merge stage's quality determines overall quality.
**Team-mode fit:** the most natural fit for agent teams. **Always build this as an agent team.** Teammates share and challenge each other's findings, and one agent's discovery can redirect another's investigation in real time — a large quality gain over isolated research.

### 3. Expert Pool
Route to the right expert per situation.

```
[router] → { expert A | expert B | expert C }
```

**Fits when:** different input types need different handling
**Example:** code review — invoke only the security/performance/architecture expert that applies
**Watch out:** the router's classification accuracy is everything.
**Team-mode fit:** subagents fit better. You invoke only the expert you need, so a standing team is wasteful.

### 4. Producer-Reviewer
A producer agent and a reviewer agent work as a pair.

```
[produce] → [review] → (on issue) → [produce] re-run
```

**Fits when:** deliverable quality matters and objective review criteria exist
**Example:** webtoon — artist produces → reviewer inspects → flagged panels regenerated
**Watch out:** set a max retry count (2–3) to prevent infinite loops.
**Team-mode fit:** agent teams help here. Use SendMessage for live producer↔reviewer feedback.

### 5. Supervisor
A central agent tracks task state and distributes work to subordinate agents dynamically.

```
         ┌→ [worker A]
[supervisor] ─┼→ [worker B]    ← supervisor distributes based on live state
         └→ [worker C]
```

**Fits when:** workload is variable or distribution must be decided at runtime
**Example:** large code migration — supervisor analyzes the file list and assigns batches to workers
**Vs. fan-out:** fan-out fixes the distribution up front; the supervisor adjusts dynamically as work progresses
**Watch out:** keep delegation units large enough that the supervisor doesn't become the bottleneck.
**Team-mode fit:** the shared task list maps naturally onto the supervisor pattern. Register work with TaskCreate; teammates claim it themselves.

### 6. Hierarchical Delegation
A higher agent delegates recursively to lower agents, decomposing a complex problem stage by stage.

```
[lead] → [team lead A] → [worker A1]
                       → [worker A2]
       → [team lead B] → [worker B1]
```

**Fits when:** the problem decomposes naturally into a hierarchy
**Example:** full-stack app — lead → frontend lead → (UI/logic/tests) + backend lead → (API/DB/tests)
**Watch out:** depth beyond 3 levels compounds latency and context loss. Keep it to 2 levels.
**Team-mode fit:** agent teams can't nest (a teammate can't create a team). Implement level 1 as a team and level 2 as subagents, or flatten into a single team.

## Composite Patterns

In practice, composite patterns are more common than single ones:

| Composite Pattern | Composition | Example |
|----------|------|------|
| **Fan-out + Producer-Reviewer** | parallel production, then individual review | multilingual translation — 4 languages translated in parallel → each reviewed by a native reviewer |
| **Pipeline + Fan-out** | parallelize some stages of a sequential flow | analysis (sequential) → implementation (parallel) → integration tests (sequential) |
| **Supervisor + Expert Pool** | supervisor dynamically invokes experts | customer-inquiry handling — supervisor classifies inquiries, assigns the right expert |

### Execution Mode in Composite Patterns

**Default to agent teams for every composite pattern.** Active teammate communication is the main driver of output quality.

| Scenario | Recommended Mode | Why |
|---------|----------|------|
| **Research + analysis** | agent team | researchers share discoveries, debate conflicting info in real time |
| **Design + implement + verify** | agent team | feedback loop across designer↔implementer↔verifier |
| **Supervisor + workers** | agent team | shared task list for dynamic assignment, progress shared across workers |
| **Produce + review** | agent team | live producer↔reviewer feedback minimizes rework |

> Mix in subagents only when a single agent does a fully isolated, one-shot task.

## Choosing an Agent Type

When invoking an agent, set its type via the `Agent` tool's `subagent_type` parameter. Team members can use custom agent definitions too.

### Built-in Types

| Type | Tool Access | Best For |
|------|----------|-----------|
| `general-purpose` | full (including WebSearch, WebFetch) | web research, general work |
| `Explore` | read-only (no Edit/Write) | codebase exploration, analysis |
| `Plan` | read-only (no Edit/Write) | architecture design, planning |

### Custom Types

Define an agent in `.claude/agents/{name}.md` and invoke it with `subagent_type: "{name}"`. Custom agents get full tool access.

### Selection Criteria

| Situation | Recommended | Why |
|------|------|------|
| Complex role reused across sessions | **custom type** (`.claude/agents/`) | persona and working principles managed as a file |
| Simple research/collection, prompt suffices | **`general-purpose`** + detailed prompt | no agent file needed; instructions live in the prompt |
| Read-only code work (analysis/review) | **`Explore`** | prevents accidental file edits |
| Design/planning only | **`Plan`** | keeps focus on analysis, blocks code changes |
| Implementation that edits files | **custom type** | full tool access + specialized instructions |

**Principle:** Define every agent as a `.claude/agents/{name}.md` file — even for built-in types. The file declares the role, principles, and protocols. Only a file persists for reuse next session, and only a stated Team Communication Protocol guarantees collaboration quality.

**Model:** Every agent uses `model: "opus"`. Always pass `model: "opus"` when calling the Agent tool.

## Agent Definition Structure

```markdown
---
name: agent-name
description: "1-2 sentence role description. List trigger keywords."
---

# Agent Name — one-line role summary

You are a [role] expert in [domain].

## Core Responsibilities
1. responsibility 1
2. responsibility 2

## Working Principles
- principle 1
- principle 2

## Input/Output Protocol
- Input: [what you receive and from where]
- Output: [what you write and where]
- Format: [file format, structure]

## Team Communication Protocol (agent-team mode)
- Receiving: [who sends you what]
- Sending: [who you send what to]
- Task claims: [what kind of work you claim from the shared task list]

## Error Handling
- [behavior on failure]
- [behavior on timeout]

## Collaboration
- relationships with other agents
```

## Splitting vs Merging Agents

| Criterion | Split | Merge |
|------|------|------|
| Expertise | different domains → split | overlapping domains → merge |
| Parallelism | independently runnable → split | sequentially dependent → consider merging |
| Context | heavy context load → split | light and fast → merge |
| Reuse | used by other teams → split | used only here → consider merging |

## Skill vs Agent

| Aspect | Skill | Agent |
|------|-------------|-----------------|
| Definition | procedural knowledge + tool bundle | expert persona + behavioral principles |
| Location | `.claude/skills/` | `.claude/agents/` |
| Trigger | matches user-request keywords | explicitly invoked via the Agent tool |
| Size | small to large (workflows) | small (role definition) |
| Purpose | "how it's done" | "who does it" |

A skill is the **procedural guide** an agent consults while working.
An agent is the **expert role definition** that puts skills to use.

## Wiring Skills to Agents

Three ways an agent can use a skill:

| Approach | Implementation | Best When |
|------|------|-----------|
| **Skill-tool call** | agent prompt says "invoke /skill-name via the Skill tool" | the skill is a standalone workflow and user-invocable |
| **Inline in prompt** | embed the skill's content directly in the agent definition | the skill is short (≤50 lines) and specific to this agent |
| **Reference load** | `Read` the skill's references/ file on demand | the skill is large and only conditionally needed |

Rule of thumb: high reuse → Skill tool; dedicated → inline; bulky → reference load.
