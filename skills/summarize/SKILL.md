---
name: summarize
description: Summarize an implementation with full context, decisions made by agent and human, and a link to the plan if applicable. Writes to $AGENT_HOME/summary.
user-invocable: true
argument-hint: optional-focus-or-filename
---

Summarize what has just been implemented in this session and persist it to `$AGENT_HOME/summary/` as an **Obsidian-friendly note** — the user opens these in Obsidian and relies on graph view to see how summaries, plans, context dumps, files, tickets, and concepts interconnect. Every cross-reference must be a wikilink (`[[...]]`) so it shows up as an edge in the graph.

## Output location

Write the summary to: `$AGENT_HOME/summary/<slug>--<YYYY-MM-DD>.md`

Naming convention:
- `<slug>`: short, kebab-case, lowercase, no spaces — describes *what was built* (e.g. `auth-middleware-rewrite`). If `$ARGUMENTS` is provided, derive the slug from it.
- `--` (double dash) separates the slug from the date so slugs containing numbers/dates stay unambiguous.
- `<YYYY-MM-DD>`: always ISO-8601 date, zero-padded. Sorts correctly and is unambiguous.
- **No time component by default** — one summary per implementation is the norm.
- **On collision** (same slug + same day): append `-HHMM` (24h local time) to the filename, e.g. `auth-middleware-rewrite--2026-04-16-1430.md`. Do NOT use `-2`, `-3` suffixes (those don't convey information and hurt graph-view readability).
- Create `summary/` if it doesn't exist.
- **Never rename after creation** — Obsidian wikilinks point at the filename. If a rename is truly needed, the user should use Obsidian's rename (which updates backlinks).

## Linking rules (critical for Obsidian graph view)

- **All in-vault references are wikilinks**: `[[note-name]]` or `[[note-name|display text]]`. Never use standard `[text](path.md)` for anything inside `$AGENT_HOME`.
- **Link the plan** as `[[plans/<plan-slug>]]` (or whatever path exists). If the plan lives elsewhere in the vault, link the note by name without extension.
- **Link sibling notes**: any related summary or context dump should be `[[summary/<other-slug>--<YYYY-MM-DD>]]` / `[[context/<other-label>--<YYYY-MM-DD>-<HHMM>]]`.
- **Link touched source files as wikilinks too** — e.g. ``[[src/auth/middleware.ts]]``. Obsidian will treat these as unresolved nodes (which is fine — it still shows them in the graph and groups them). Wrap the wikilink in backticks inside prose when you also want it to render as code: `` `[[src/auth/middleware.ts]]` ``.
- **Concept / tag nodes**: use wikilinks like `[[concept/rbac]]`, `[[concept/session-tokens]]` for the load-bearing ideas in the work. These become hub nodes in the graph.
- **Tickets / PRs / external IDs**: link as `[[INGEST-482]]`, `[[PR-1234]]`. External URLs stay as plain markdown links (those don't belong in the vault graph).
- **Frontmatter aliases**: include an `aliases:` list if the work has alternate names people might search for — Obsidian uses aliases to resolve wikilinks.
- **Tags**: use `tags:` in frontmatter (not inline `#tag`) for session metadata (e.g. `summary`, project name) — these give graph view color filters.

## File structure

```markdown
---
bd: bd-xxx   # or "none" if this work wasn't tracked in beads
title: <human-readable title>
date: <YYYY-MM-DD>
aliases: []
tags: [summary, <project-or-area>]
private: false   # true = personal/side-project, skip team sync
plan: "[[plan/bd-xxx-<slug>]]"   # or "none"
sessions:
  - <uuid-of-session-finalizing-this-summary>   # from $CLAUDE_SESSION_ID
---

# <title>

## What was built
<1–3 paragraph narrative. Inline-link every concept / file / ticket as a wikilink so the graph picks it up.>

## Plan
- [[plan/bd-xxx-<slug>]]   <!-- or say "inline only — see below" and include it verbatim -->

## Files touched
- `[[<repo-relative-path>]]` — <one-line reason>
- ...

## Key decisions
- **<decision>** — <rationale>. Decided by: <agent | user | both>. Related: [[concept/<idea>]]
- ...

## Context worth preserving
<non-obvious constraints, gotchas, tickets like [[INGEST-482]], things a future reader would miss from the diff alone>

## Related notes
- [[summary/<previous-related-slug>--<YYYY-MM-DD>]]
- [[context/<related-dump>--<YYYY-MM-DD>-<HHMM>]]
- [[concept/<hub-idea>]]

## Follow-ups / known gaps
- <anything deferred, flagged, or left as TODO> — link tickets as [[...]]

## Verification
<how the change was validated — tests run, manual checks, what was NOT verified>

## Persona reviews
<Appended in step 7. Per-persona blocks from `bdx.persona auto` over this summary, each under a `### <persona-name>` subheader, verbatim. Section is absent if no personas matched.>
```

## Rules

- **Attribute decisions.** For each non-trivial decision, note whether the agent chose it, the user chose it, or both agreed. If unclear, say "agent default, unchallenged by user" — don't fabricate.
- **Capture the why, not the what.** The diff shows *what*. The summary preserves intent, alternatives considered, and constraints.
- **Do not re-derive from code.** Don't paste large diffs or list every function signature. Link files as wikilinks and describe intent.
- **Be honest about gaps.** If something was skipped, stubbed, or not tested, say so.
- **Keep it terse.** Handoff note, not a design doc — skimmable in under two minutes.
- **Every cross-reference is a wikilink.** If you catch yourself writing `[text](path.md)` for a vault note, convert it.
- **`private: false` by default.** Summaries are the strongest team-sync candidate — flip to `true` only for personal/side-project work. The sync layer honors the flag.
- **Persona blocks are pasted verbatim.** When the persona pass returns output, paste it as-is — don't smooth contradictions between personas, don't pick a winner, don't rewrite into wikilink style. The voices and disagreements are the value. The summary's own sections still follow all the linking rules; the persona section is an exception.

## Process

1. `mkdir -p "$AGENT_HOME/summary"`.
2. Identify the bd-id: from `$ARGUMENTS`, the plan file name in conversation, or ask. If the work truly has no bd issue, set `bd: none` in frontmatter and skip step 8 (the bd comment cross-link).
3. Decide the slug and final path; check for collisions.
4. Read `$CLAUDE_SESSION_ID` (set by SessionStart hook). If empty, set `sessions: []`.
5. Scan the conversation for: original request, plan, decisions, file changes, verification steps, unresolved items, related prior summaries/context dumps.
6. Write the file using the template above, with wikilinks everywhere and `$CLAUDE_SESSION_ID` in `sessions:`. Do not include the `## Persona reviews` section yet — step 7 appends it if personas return output.
7. **Persona pass.** Follow the `persona` skill's instructions inline with the following free-form prompt as `$ARGUMENTS` (substitute the real path):

   ```
   auto You are about to critique an implementation that was just shipped. The full writeup — what was built, files touched, key decisions, tradeoffs, what's verified, what's deferred — is at <full-path-to-just-written-summary>. Read it as evidence about the work and react to the work itself: the decisions, the scope, the approach, what was skipped or stubbed, what looks load-bearing vs. fragile. You are NOT reviewing the prose of the summary document — do not edit its wording, structure, or word choice. The summary is the lens onto the implementation; the implementation is the target.
   ```

   The persona skill's free-form path will pass this through verbatim so the selected personas know the summary file is *evidence about the work*, not the artifact under review. The persona skill returns per-persona blocks, or "no matching persona" with no output.
   - If output was returned: `Edit` the file to append a `## Persona reviews` section at the end, with each persona's block under a `### <persona-name>` subheader, verbatim.
   - If no persona matched: do nothing — the section stays absent. Do not block the summary on persona availability.
   - Do not re-invoke a persona that already gave a take in this session's conversation — skip it to avoid duplicating output the user already saw.
8. Cross-link back to beads: `bd comment <bd-id> "summary: $AGENT_HOME/summary/<slug>--<date>.md"` — makes the summary discoverable from `bd show`.
9. Report the path back to the user in one line.

## When the work is done

`summarize` does **not** close the beads issue — that's the user's call via `bd close <id> -r "<resolution>"`. Writing the summary and closing are distinct acts: you can have a finished summary with follow-ups still tracked on the same open issue.
