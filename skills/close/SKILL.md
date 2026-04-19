---
name: close
description: Finalize a beads task. Ensures a summary exists (runs summarize if missing), then closes the bd issue with a resolution message.
user-invocable: true
argument-hint: bd-id [and/or resolution message]
---

Close out a finished (or abandoned) task: verify a summary exists for the beads issue, and `bd close` it with a resolution. This is the **finalize** step of the `plan` → `dump` → `summarize` → `close` flow.

Closing is deliberately separate from summarizing — a task can have a written summary and still have follow-ups open. Closing means "this is actually done." Zombie issues (summary written, bd never closed) are the failure mode this skill prevents.

## What this skill does (in order)

1. Parse `$ARGUMENTS` for the bd-id and optional resolution message. If the bd-id is missing, infer from the active conversation or plan file in context; ask the user if still ambiguous.
2. Check for an existing summary: `grep -l "^bd: <bd-id>$" "$AGENT_HOME/summary"/*.md` (a summary is any file with the matching `bd:` frontmatter line). Run this in parallel with step 1's id resolution when possible.
3. **If no summary exists**, run the full `summarize` process for this bd-id before continuing. Do not skip this — summaries are the durable record of the work; a close without one loses history.
4. Resolve the resolution message:
   - If passed in `$ARGUMENTS` → use it.
   - If `$ARGUMENTS` contains "abandon" / "kill" / "drop" → default to `"abandoned: <verbatim-trailing-text>"`.
   - Otherwise → default silently to `"done"`. Do **not** prompt — the summary is the durable record; the resolution is a one-line tombstone and "done" is fine for the clean-completion case.
   - Only prompt if the close is ambiguous (e.g. summary mentions unresolved follow-ups and the user hasn't signaled intent).
5. Close the issue: `BDX_ALLOW_BARE_BD_CLOSE=1 bd close <bd-id> -r "<resolution>"`. The inline env assignment signals the plugin's guard hook to allow this close through; without it the hook blocks all bare `bd close` calls.
6. Report: bd-id, resolution, and the summary path.

## Resolution message guidance

- **Clean completion**: `"done"`, `"shipped in PR-1234"`, `"merged 2026-04-16"`.
- **Abandoned**: always prefix with `"abandoned: "` followed by the reason. Keeps `bd list -s closed` grep-able for "why did this die?"
- **Superseded by another task**: `"superseded by bd-yyy"` (and consider `bd supersede <bd-xxx> --with <bd-yyy>` instead of `bd close` — it creates a formal link).
- **One line, past tense.** The summary file holds the full story; the resolution is the one-sentence tombstone.

## Rules

- **Never close without a summary.** If step 3 fails (the user declines to summarize, or summarize errors), abort the close and tell the user why. Better to leave the issue open than to lose the record.
- **Don't edit the summary to reflect the close.** The summary is past-tense; closing is an act after. Keep them independent.
- **Don't file follow-ups automatically.** If the summary mentions "Follow-ups / known gaps", report them to the user so they can decide what to file — but don't auto-create issues. Agent-generated backlog noise is the other failure mode this skill avoids.
- **Closing an abandoned plan is valid and should be easy.** If the user says "kill it" or similar, run summarize first (to capture *why* it was abandoned — decisions worth preserving even for dead work), then close with `"abandoned: <reason>"`.

## Process

1. Resolve the bd-id (from `$ARGUMENTS`, active plan file, or ask).
2. **Single batched message** — run in parallel: summary grep (`grep -l "^bd: <bd-id>$" "$AGENT_HOME/summary"/*.md 2>/dev/null`), and `bd show <bd-id>` to confirm the issue exists and is closeable.
3. Resolve the resolution: `$ARGUMENTS` if passed, `"abandoned: ..."` on abandon-signal keywords, else `"done"`. No prompt for the clean case.
4. If no summary is found → invoke the `summarize` process (follow that skill's instructions end-to-end, with this bd-id). After it writes the summary, continue.
5. Run `BDX_ALLOW_BARE_BD_CLOSE=1 bd close <bd-id> -r "<resolution>"`.
6. Report one line: `Closed <bd-id>: "<resolution>" — summary at <path>`.
