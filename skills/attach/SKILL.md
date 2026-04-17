---
name: attach
description: Attach the current Claude session to an existing beads task. Loads plan/context/summary artifacts, marks the session in the plan's sessions list, and sets bd status to in_progress.
user-invocable: true
argument-hint: bd-id
---

Tap the current session into an existing beads issue / plan so Claude picks up cold with full task state. This is the counterpart to `plan` (which creates a new task): `attach` resumes an existing one.

Use when:
- You want to continue work on `bd-xxx` in a fresh session
- You resumed via `claude --resume <uuid>` and also want the plan updated with this session (if it's a different UUID)
- You're starting a session and want state loaded without recreating a plan

## What this skill does (in order)

1. Resolve the bd-id from `$ARGUMENTS`. If missing, ask the user — do not guess.
2. **Load task state** (read-only first):
   - `bd show <bd-id>` — issue details, description, labels, status, blockers
   - `bd comments <bd-id>` — all prior comments (these contain links to summaries/contexts from summarize / dump)
   - Find the plan: `ls $AGENT_HOME/plan/<bd-id>-*.md` (typically one match)
   - Find prior context dumps: `grep -l "^bd: <bd-id>$" "$AGENT_HOME/context"/*.md 2>/dev/null`
   - Find prior summaries: `grep -l "^bd: <bd-id>$" "$AGENT_HOME/summary"/*.md 2>/dev/null`
   - **Look up the project** in `$AGENT_HOME/manifest.md` using the project label from `bd show` — pull `path`, `type`, and `notes` for the briefing. If the project isn't in the manifest, flag it (the user may need to add it).
   - Read the plan file end-to-end. Read the most recent context dump (if any) end-to-end. Skim summaries.
3. **Attach the session** (mutate):
   - If `$CLAUDE_SESSION_ID` is set, open the plan file's frontmatter `sessions:` list. If the UUID isn't already present, append it. If the list doesn't exist, create it.
   - If `$CLAUDE_SESSION_ID` is empty (e.g. running in `--print` mode or the hook didn't fire), skip silently — do not fail.
4. **Update bd status**: if the issue is `open`, run `bd update <bd-id> --status in_progress`. If already `in_progress`, `blocked`, `deferred`, or `closed`, leave it alone. If `closed`, warn the user and ask whether to `bd reopen` before continuing.
5. **Brief the user**: print a concise summary covering:
   - Project blurb from the manifest (path + 1-line description) — so you remember what this project is
   - Title, status, priority, labels
   - Plan path + 3–5 line overview of the goal/scope (not the full plan)
   - Last 2–3 bd comments (newest first)
   - Paths to the most recent context dump and summary if they exist
   - Next uncompleted checkbox from the plan, if applicable ("Pick up at: <step>")
6. Report one line: `Attached to <bd-id> (<title>) — plan: <path>`.

## Rules

- **Read before mutate.** Step 2 is entirely read-only so the user sees state before anything changes. Only step 3 writes.
- **Don't re-plan.** If the plan feels stale or wrong, do NOT overwrite it — flag it to the user and let them decide whether to `plan` a new task or edit the existing plan manually. Plans are append-only in spirit.
- **Don't dump context here.** attach only reads. Use `dump` separately if you want to snapshot current state before continuing.
- **Don't close or comment on the bd issue.** Attaching is a load operation, not a status broadcast. The only state change is `open → in_progress`.
- **Ambiguous bd-id**: if the user passed a slug instead of a bd-id, try `bd search "<slug>"` and present matches; don't auto-pick.
- **Preserve all other frontmatter.** When appending to the plan's `sessions:` list, every other key — `bd:`, `title:`, `created:`, `aliases:`, `tags:`, `private:`, `status:`, `external:`, anything user-added — must round-trip untouched.

## Process

1. Resolve bd-id from `$ARGUMENTS`; ask if missing.
2. Run `bd show <bd-id>`, `bd comments <bd-id>` (capture outputs).
3. Locate and read the plan: `$AGENT_HOME/plan/<bd-id>-*.md`.
4. Locate prior contexts/summaries via grep on `bd: <bd-id>`.
5. If `$CLAUDE_SESSION_ID` set and not already in the plan's `sessions:` frontmatter, append it.
6. If bd status is `open`, `bd update <bd-id> --status in_progress`. If `closed`, warn + prompt.
7. Print the briefing (title, status, plan overview, recent comments, next step).
8. Report the one-line confirmation.
