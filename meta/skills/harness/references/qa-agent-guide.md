# QA Agent Design Guide

Reference for including a QA agent in a build harness. Drawn from bug patterns and root-cause analysis observed in a real project (SatangSlide), it offers a verification methodology for systematically catching the defects QA most often misses.

---

## Contents

1. Defect patterns QA agents miss
2. Integration consistency verification (Integration Coherence Verification)
3. QA agent design principles
4. Verification checklist template
5. QA agent definition template

---

## 1. Defect patterns QA agents miss

### 1-1. Boundary mismatch

The most common defect. Both components are individually "correct," but the contract between them diverges at the connection point.

| Boundary | Mismatch example | Why it slips through |
|--------|-----------|-----------|
| API response → frontend hook | API returns `{ projects: [...] }`, hook expects `SlideProject[]` | Each checks out in isolation; no cross-comparison happens |
| API response field name → type definition | API uses `thumbnailUrl` (camelCase), type uses `thumbnail_url` (snake_case) | A TypeScript generic cast hides it from the compiler |
| File path → link href | Page lives at `/dashboard/create` but the link points to `/create` | File structure and href are never cross-checked |
| State transition map → actual status update | Map defines `generating_template → template_approved`, but the code never makes the transition | Only the map's existence is confirmed; not every update site is traced |
| API endpoint → frontend hook | API exists but no hook calls it (dead endpoint) | Endpoints and hooks are never matched 1:1 |
| Immediate response → async result | API returns `{ status }` immediately; frontend reads `data.failedIndices` | Types match, so the sync/async distinction goes unnoticed |

### 1-2. Why static code review misses these

- **The limits of TypeScript generics**: `fetchJson<SlideProject[]>()` compiles even when the runtime response is `{ projects: [...] }`
- **`npm run build` passing ≠ correct behavior**: with type casts, `any`, or generics, the build succeeds but runtime fails
- **Existence vs. connection**: "Does the API exist?" and "Does the API's response match what the caller expects?" are entirely different questions

---

## 2. Integration consistency verification (Integration Coherence Verification)

The **cross-boundary comparison** checks a QA agent must always perform.

### 2-1. API response ↔ frontend hook type cross-check

**How**: Compare each API route's `NextResponse.json()` call against the type parameter of the `fetchJson<T>` in its hook.

```
Steps:
1. Extract the shape of the object passed to NextResponse.json() in the API route
2. Read the T in the hook's fetchJson<T>
3. Compare the shape against T
4. Check wrapping (if the API returns { data: [...] }, does the hook unwrap .data?)
```

**Watch especially for:**
- Paginated APIs: `{ items: [], total, page }` vs. a frontend expecting an array
- snake_case DB field → camelCase API response → frontend type definition mismatches
- Shape differences between an immediate response (202 Accepted) and the final result

### 2-2. File path ↔ link/router path mapping

**How**: Derive URL paths from page files under `src/app/` and compare them against every `href`, `router.push()`, and `redirect()` value in the code.

```
Steps:
1. Derive URL patterns from page.tsx paths under src/app/
   - (group) → stripped from the URL
   - [param] → dynamic segment
2. Collect every href=, router.push(, redirect( value in the code
3. Confirm each link matches an actually-existing page path
4. Mind the URL prefix of pages inside a route group (e.g. under dashboard/)
```

### 2-3. State transition completeness tracing

**How**: Extract every `status:` update from the code and compare against the state transition map.

```
Steps:
1. Extract the allowed transitions from the state transition map (STATE_TRANSITIONS)
2. Search every API route for .update({ status: "..." }) patterns
3. Confirm each transition is defined in the map
4. Identify map transitions the code never executes (dead transitions)
5. In particular: make sure the move from an intermediate state (e.g. generating_template) to a final state (template_approved) isn't missing
```

### 2-4. API endpoint ↔ frontend hook 1:1 mapping

**How**: List every API route and every frontend hook, then confirm they pair up.

```
Steps:
1. Extract the endpoints per HTTP method from route.ts files under src/app/api/
2. Extract the fetch URLs from use*.ts files under src/hooks/
3. Flag any endpoint no hook calls as "unused"
4. Decide whether "unused" is intentional (e.g. an admin API) or a missing call
```

---

## 3. QA agent design principles

### 3-1. Use the general-purpose type, not Explore

An `Explore`-type QA agent can only read. But effective QA needs to:
- Search patterns with Grep (extract every `NextResponse.json()`)
- Run scripts to cross-check automatically (API shape vs. hook type)
- Fix issues when needed

**Recommended**: Use `general-purpose`, and spell out a "verify → report → request fix" protocol in the agent definition.

### 3-2. Prefer "cross-comparison" over "existence checks" in the checklist

| Weak checklist | Strong checklist |
|---------------|---------------|
| Does the API endpoint exist? | Does the endpoint's response shape match the hook's type? |
| Is the state transition map defined? | Does every status-update site match a transition in the map? |
| Does the page file exist? | Does every link in the code point to a page that exists? |
| Is TypeScript in strict mode? | Is any type safety bypassed by a generic cast? |

### 3-3. The "read both sides at once" principle

To catch cross-boundary bugs, QA cannot read just one side. Always open and read them together:
- the API route **and** its hook
- the state transition map **and** the actual update code
- the file structure **and** the link paths

State this principle explicitly in the agent definition.

### 3-4. Run QA right after each module, not after the build

Placing QA only at "Phase 4: after everything is built" means:
- bugs accumulate, raising the cost of fixing them
- early boundary mismatches propagate into later modules

**Recommended pattern**: incremental QA — as each backend API is finished, immediately cross-check that API against its hook.

---

## 4. Verification checklist template

An integration-consistency checklist for web applications, to embed in the QA agent definition.

```markdown
### Integration consistency verification (web app)

#### API ↔ frontend connection
- [ ] Every API route's response shape matches its hook's generic type
- [ ] Wrapped responses ({ items: [...] }) are unwrapped in the hook
- [ ] snake_case ↔ camelCase conversion is applied consistently
- [ ] The frontend distinguishes an immediate response (202) from the final result
- [ ] Every API endpoint has a corresponding hook that actually calls it

#### Routing consistency
- [ ] Every href/router.push value in the code matches a real page file path
- [ ] Path checks account for route groups ((group)) being stripped from the URL
- [ ] Dynamic segments ([id]) are filled with the correct parameter

#### State machine consistency
- [ ] Every defined transition is executed somewhere in the code (no dead transitions)
- [ ] Every status update in the code is defined in the transition map (no rogue transitions)
- [ ] No intermediate-to-final transition is missing
- [ ] In status-based branches (if status === "X"), X is actually reachable

#### Data flow consistency
- [ ] DB schema field names map consistently to API response field names
- [ ] Frontend type definitions and API response field names agree
- [ ] null/undefined handling for optional fields is consistent on both sides
```

---

## 5. QA agent definition template

The core sections to include in a build harness's QA agent.

```markdown
---
name: qa-inspector
description: "QA verification specialist. Verifies spec compliance, integration consistency, and design quality."
---

# QA Inspector

## Core role
Verify implementation quality against the spec, and **cross-module integration consistency**.

## Verification priority

1. **Integration consistency** (highest) — boundary mismatch is the leading cause of runtime errors
2. **Functional spec compliance** — API / state machine / data model
3. **Design quality** — color / typography / responsiveness
4. **Code quality** — dead code, naming conventions

## Method: "read both sides at once"

Boundary checks require opening **both sides at once** to compare:

| Target | Left (producer) | Right (consumer) |
|----------|-------------|---------------|
| API response shape | route.ts NextResponse.json() | hooks/ fetchJson<T> |
| Routing | src/app/ page file path | href, router.push value |
| State transition | STATE_TRANSITIONS map | .update({ status }) code |
| DB → API → UI | table column name | API response field → type definition |

## Team communication protocol

- On discovery, send a concrete fix request to the responsible agent (file:line + how to fix)
- Notify **both** agents about a boundary issue
- To the lead: a verification report (separating passed / failed / unverified items)
```

---

## Case study: bugs found in SatangSlide

Everything in this guide is distilled from these real bugs:

| Bug | Boundary | Cause |
|------|--------|------|
| `projects?.filter is not a function` | API→hook | API returned `{projects:[]}`, hook expected an array |
| Every dashboard link 404s | file path→href | Missing `/dashboard/` prefix |
| Theme images don't show | API→component | `thumbnailUrl` vs `thumbnail_url` |
| Theme selection won't save | API→hook | select-theme API existed, no hook |
| Create page waits forever | state transition→code | `template_approved` transition code missing |
| `data.failedIndices` crash | immediate response→frontend | Read a background result off the immediate response |
| "View slides" 404s after completion | file path→href | `/projects/` → `/dashboard/projects/` |
