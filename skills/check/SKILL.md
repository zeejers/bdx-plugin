---
name: check
description: Tick one or more checkboxes on a bd's plan file — atomic, append-only, no context/summary side effects. Use when a step from the plan is done and you want the plan to reflect it (so peeking at the plan shows real progress) without writing a context dump or summary. Skip if the work warrants a full mid-session snapshot (use `dump`) or is shipped (use `summarize`). Skip also for adding new checkboxes — edit the plan directly.
user-invocable: true
argument-hint: bd-id "<checkbox-fragment>" [--note "<inline-divergence>"]
---

Flip one or more `- [ ]` checkboxes to `- [x]` on the bd's plan file. The cheap primitive: no context file, no summary, no bd state change beyond an optional progress comment. Lets the plan stay live as a "what's done so far" view without forcing the user through `dump`'s heavier ceremony.

**Trigger**: a verifiable step from the plan just finished and you want the plan to show it. **Skip** if (a) you're about to log out / hand off — `dump` ticks boxes *and* snapshots head-state, (b) the work is shipped — `summarize` is the right closer, (c) you want to add a new checkbox or restructure the plan — open the plan and edit it directly.

## What this skill does (in order)

1. Resolve the bd-id (from `$ARGUMENTS`, `$BD_ID`, or the conversation context). Required.
2. Locate the plan file: `$AGENT_HOME/plan/<bd-id>-*.md`. If missing, fail loudly — `check` is plan-only; bds without plans should use `bd comment` instead.
3. Match the checkbox fragment against open `- [ ]` lines in the plan, case-insensitive substring (or the user's full line). On ambiguity, list candidates and stop. On zero matches, fail loudly.
4. Edit the matched line: `- [ ]` → `- [x]`.
5. If `--note "<text>"` was passed, append ` → <text>` to the same line (one-liner inline divergence — see Annotation rules below).
6. Append the session UUID to the plan's `sessions:` frontmatter list if it's not already there (reuse the same logic as `attach`/`dump`).
7. Optional: `bd comment <bd-id> "checked: <matched checkbox text>"` so the bd's comment thread reflects step-by-step progress. Skip the comment if the user passed `--quiet`.
8. Report: `bd-xxx · ticked <N> box(es) · plan/<filename>` in one line.

## Annotation rules (`--note`)

The `--note` flag is for *small* divergences from the original spec — a renamed file, a slightly different path, a swapped library. Anything bigger belongs in `summarize` or a `bd comment`, not on the checkbox.

- **One line, no markdown beyond inline code.** `→ moved to /api/v2/users` ✓ · `→ See discussion in $AGENT_HOME/context/...` ✗
- **Append, never replace.** The original checkbox text stays intact; the note follows the ` → ` separator.
- **Single annotation per checkbox.** If a step diverged twice, write a fresh annotation that supersedes — don't chain `→ a → b → c`.

## Multiple checkboxes per call

If the fragment is a comma-separated list (`"add endpoint, wire frontend"`), match each fragment independently, tick each match, and report the count. If any one fragment is ambiguous or unmatched, fail the whole call — partial ticks are confusing.

## What this skill never does

- **Never adds a new checkbox.** Plan structure is the user's call; opening the plan and editing it directly is the right path.
- **Never unticks (`[x]` → `[ ]`).** Treat ticks as append-only progress. If you genuinely need to unwind, edit the plan directly.
- **Never rewrites prose, reorders sections, or touches anything outside the matched checkbox line.** That's `summarize`'s territory if anything's, and even there the default is to leave the plan intact.
- **Never writes to `$AGENT_HOME/context/` or `$AGENT_HOME/summary/`.** Those are for `dump` and `summarize` respectively.

## Examples

```
/bdx:check bd-uj66 "wire dump checkbox-tick logic"
→ bd-uj66 · ticked 1 box · plan/bd-uj66-add-bdx-check.md

/bdx:check bd-uj66 "add /api/users endpoint" --note "moved to /api/v2/users"
→ bd-uj66 · ticked 1 box · plan/bd-uj66-add-bdx-check.md
   (- [x] add /api/users endpoint → moved to /api/v2/users)

/bdx:check bd-uj66 "thing-that-doesnt-exist"
→ no matching open checkbox in plan/bd-uj66-add-bdx-check.md. open boxes:
   - add /api/users endpoint
   - wire frontend form
   - update tests
```

## Process

1. Resolve `<bd-id>` from `$ARGUMENTS` (first positional). Fall back to `$BD_ID` env, then to the active plan file in conversation. If unresolvable, fail.
2. `ls "$AGENT_HOME/plan/<bd-id>-"*.md` — expect exactly one match. Fail otherwise.
3. Read the plan file. Extract every `- [ ] <text>` line with its line number.
4. For each fragment in `$ARGUMENTS` (split on `,`), find the unique open checkbox whose text contains the fragment (case-insensitive substring). On ambiguity or zero match, abort and print candidates.
5. For each match: `Edit` the plan file, replacing `- [ ] <full text>` with `- [x] <full text>` (plus ` → <note>` if `--note` was supplied).
6. Read `$CLAUDE_SESSION_ID`. If set and not already in the plan's `sessions:` list, append it.
7. Unless `--quiet`: `bd comment <bd-id> "checked: <text>"` for each ticked box (one comment per box keeps the bd thread granular).
8. Report the count and plan path on one line.

## Resuming

`check` is fire-and-forget — there's no in-flight state to resume. The plan file's `sessions:` list still records which session ticked which boxes (via the append in step 6), so `git log` on the vault and the bd comment thread together reconstruct the order.
