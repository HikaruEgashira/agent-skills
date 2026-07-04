# fable-guard

Auto-recover from **Fable 5 no-fallback refusals**.

Claude Fable 5 runs safety classifiers (cybersecurity / biology). When a request
is flagged, Claude Code normally falls back to Opus. If you set
`switchModelsOnFlag: false` to keep sessions on Fable, the flagged turn instead
ends with a **refusal** and no automatic recovery. `fable-guard` closes that gap:
a `Stop` hook detects the refusal and drives `/compact` + reprompt through the
**herdr** socket API — the only actuator able to inject a slash command into the
live TUI (hooks cannot trigger `/` commands themselves).

## How it works

```
Stop hook
  └─ refusal-dispatch.sh   (fast, <1s, never blocks the reply)
       ├─ read stdin JSON, guard against loops (stop_hook_active)
       ├─ require a herdr session (HERDR_ENV + live socket)
       ├─ detect: last "promptSource: typed" turn was answered with a
       │          system entry subtype "model_refusal_no_fallback"
       ├─ enforce a per-prompt retry cap (default 2)
       └─ detach → refusal-recover.sh   (background worker)
                     ├─ herdr agent wait <pane> --status idle
                     ├─ herdr pane send-text <pane> "/compact" + enter
                     ├─ wait for compact to finish
                     └─ resubmit the last typed prompt
```

Detection reads only the transcript tail, so it stays cheap on long sessions.
The dispatcher passes **only paths/ids** to the worker via `FG_RT_*` env vars and
writes the reprompt to a file — transcript content is never interpolated into a
command string.

## Requirements

- Running inside a **herdr** session (`HERDR_ENV=1`, live `HERDR_SOCKET_PATH`).
  Outside herdr the hook detects the refusal but cannot act, so it no-ops.
- `jq` on `PATH`.

## Configuration (environment variables)

| Variable | Default | Meaning |
| --- | --- | --- |
| `FABLE_GUARD_DISABLE` | `0` | `1` disables the hook entirely (kill switch). |
| `FABLE_GUARD_MODE` | `recover` | `recover` = auto compact + reprompt; `notify` = only alert, never touch the prompt. |
| `FABLE_GUARD_MAX_RETRIES` | `2` | Auto-retries per offending prompt before falling back to notify-only. The counter resets when a different prompt refuses. |
| `FABLE_GUARD_COMPACT` | `1` | `0` skips `/compact` and only resubmits. |
| `FABLE_GUARD_REPROMPT` | *(unset)* | Fixed reprompt text to send instead of resubmitting the original prompt. |

## Limits (read this)

- `/compact` shrinks the **conversation history**. It helps when the refusal was
  triggered by *accumulated history* (e.g. an earlier security discussion). It
  does **not** help when the trigger is *static first-request context* —
  `CLAUDE.md`, git status, directory names — which is attached to every request
  regardless of compaction. For those, the retry cap trips and the hook falls
  back to notify-only. Use `claude --safe-mode` to confirm whether customizations
  are the trigger.
- Resubmitting the *same* prompt can be flagged again deterministically. The
  per-prompt retry cap bounds this; tune `FABLE_GUARD_REPROMPT` if you want a
  reworded retry instead.

## State & logs

Under `${XDG_STATE_HOME:-$HOME/.local/state}/fable-guard/`:
`log` (diagnostics), and per-session `retry.count` / `retry.key` / `reprompt.txt`
/ `lock`.
