---
name: dump
description: Snapshot mid-session head-state to $AGENT_HOME/context/ so the user can fearlessly log out and a future `attach` can re-enter cold. Also sweeps the plan for obviously-done checkboxes and ticks them (with optional one-line divergence annotations) so the plan stays a live progress view. Use when the user is about to walk away from a session (closing the tab, switching tasks, end-of-day) and the work isn't ready to summarize. Skip if a single step just finished and you only want the plan ticked — use `check` for that lighter operation.
user-invocable: true
argument-hint: optional-label
---

Snapshot the current session's head-state to `$AGENT_HOME/context/` so the user can close the session without losing the thread — a future `attach` re-enters cold and picks up where this left off. Written as an **Obsidian-friendly note**: graph view shows how the dump connects to summaries, plans, files, concepts, and tickets, so every in-vault cross-reference is a wikilink (`[[...]]`).

Trigger is *the act of leaving*, not "mid-flight notes". If the user is still actively working but a step just finished, prefer `check` (cheap, ticks one checkbox) or a `bd comment` (state). `dump` is for the moment before context is lost.

This is broader and lossier than `summarize` — it captures conversational state (what the user wants, what's been tried, what's pending) rather than a clean post-implementation writeup. If the work is *done*, run `summarize` instead.

## Plan mutation: tick + annotate, never rewrite

`dump` doubles as a final progress sweep on the plan. Before writing the context file:

- **Tick any `- [ ]` whose work is clearly finished** based on the conversation. Conservative — leave it open if there's any doubt. The plan file's role as a live progress view is exactly what makes peeking at it useful, but a falsely-ticked box poisons that.
- **Optionally append one inline divergence annotation** per ticked box, in the form `- [x] <original text> → <one-line divergence>`. Same rules as `check`'s `--note`: single line, no markdown beyond inline code, append-only — never rewrite the original checkbox text.
- **Never rewrite descriptive prose, reorder sections, delete content, or restructure the plan.** The plan-as-prompt diff against the eventual summary is load-bearing — that's how a future reader sees "what we set out to do" vs "what shipped." `dump` preserves it; `summarize` is where any prose-level reflection lives, and even there the default is to leave the plan intact.
- **Append `$CLAUDE_SESSION_ID` to the plan's `sessions:` frontmatter** if not already present.

If the plan needs structural change (a new phase, a deleted step, a reframed goal), that's a signal the task's shape has shifted and the user should decide explicitly — not a mutation `dump` should make on its own.

## Output location

Write to: `$AGENT_HOME/context/<label>--<YYYY-MM-DD>-<HHMM>.md`

Naming convention:

- `<label>`: short, kebab-case, lowercase, no spaces — describes the _session topic_ (e.g. `debugging-ingest-backpressure`). Derived from `$ARGUMENTS` if provided.
- `--` (double dash) separates the label from the timestamp so labels containing numbers/dates stay unambiguous.
- `<YYYY-MM-DD>-<HHMM>`: ISO date plus 24h local time, zero-padded (e.g. `2026-04-16-1430`). Context dumps happen multiple times per day, so the time is mandatory.
- Create `context/` if it doesn't exist.
- **On the rare collision** (same label + same minute): append `-2`, `-3`. Better: pick a more specific label.
- **Never rename after creation** — Obsidian wikilinks point at the filename. If truly needed, use Obsidian's rename (which updates backlinks).

## Linking rules (critical for Obsidian graph view)

- **All in-vault references are wikilinks**: `[[note-name]]` or `[[note-name|display]]`. Never use `[text](path.md)` for anything inside `$AGENT_HOME`.
- **Link files as wikilinks** — e.g. `[[src/jobs/ingest.ts]]`. Unresolved wikilinks still appear in the graph and cluster by name, which is what we want.
- **Link concepts** as `[[concept/<idea>]]` (e.g. `[[concept/backpressure]]`, `[[concept/rbac]]`) so repeated ideas become hub nodes.
- **Link tickets / PRs** as `[[INGEST-482]]`, `[[PR-1234]]`.
- **Link related summaries or prior dumps** as `[[summary/<slug>--<YYYY-MM-DD>]]` or `[[context/<label>--<YYYY-MM-DD>-<HHMM>]]` — this is what lets graph view show trails across sessions.
- **Frontmatter `tags:`** — always include `context` plus the project/area tag, so graph view can color-filter.
- **Frontmatter `aliases:`** — add alternate names for the session topic so other notes resolve to this dump.
- External URLs (non-vault) stay as plain markdown links — those aren't part of the graph.

## File structure

```markdown
---
bd: bd-xxx # or "none" if this dump isn't tied to a specific beads issue
kind: agent-note   # marks this as a bdx-generated artifact for vault-wide filtering
parent:   # bd-yyy if the dump's bd has a parent-child link in bd. Empty = root-level. Read from `bd dep list <id> --type parent-child`. bd is canonical.
title: <human-readable label or session topic>   # used to be `label:` — standardized on `title:` across all artifact types
created: <YYYY-MM-DD>
cwd: <current working directory>
aliases: []
tags: [context, <project-or-area>]
private: false # true = personal/side-project, skip team sync
sessions:
  - <uuid-of-session-producing-this-dump> # from $CLAUDE_SESSION_ID
related:
  - "[[summary/<related-slug>--<date>]]"
  - "[[plan/bd-xxx-<slug>]]"
---

# Session context dump — <label>

## User's goal

<in the user's words where possible; link concepts as [[concept/...]]>

## Current state

<where we are right now — mid-implementation? debugging? planning?>

## Relevant files / locations

- `[[<repo-relative-path>]]` — <why it matters>
- ...

## What's been tried

- <action> → <outcome>. Related: [[concept/<idea>]] / [[<file>]]
- ...

## Open questions / decisions pending

- <question>, options considered: [[concept/<option-a>]] vs [[concept/<option-b>]]

## Constraints and preferences surfaced

- <anything the user said about how they want this done — tooling, conventions, hard "no"s>

## External references

- Tickets: [[INGEST-482]], [[INGEST-500]]
- PRs: [[PR-1234]]
- Docs/URLs (external): [Some doc](https://...)

## Active TODOs

- <pending task> — related [[...]]

## Related notes

- [[summary/<slug>--<YYYY-MM-DD>]]
- [[context/<other-label>--<YYYY-MM-DD>-<HHMM>]]
- [[concept/<hub-idea>]]

## Raw excerpts worth keeping verbatim

<quotes, error messages, command outputs, or snippets that would lose meaning if paraphrased>
```

## Rules

- **The trigger is leaving, not noting.** If the user is still working, write a `bd comment` or edit the plan instead. `dump` exists so the user can log out cold without losing the thread.
- **Prefer signal over volume.** Skip chitchat, resolved detours, and anything trivially re-derivable from the repo.
- **Preserve verbatim what matters verbatim.** Exact error messages, exact user phrasing on preferences, exact command outputs — paste these, don't paraphrase.
- **Don't invent.** If you don't know a section's answer, write "unknown" or omit. Never guess.
- **Don't duplicate `summarize`.** If the work is done and clean, prefer `summarize`. Use `dump` when work is mid-flight and the session is about to end.
- **Capture constraints, not just content.** "User hates emoji in code", "must stay on Node 18", "can't touch auth without review" — these are load-bearing.
- **Include cwd and timestamp** so the dump is interpretable out of context.
- **Every cross-reference is a wikilink.** If you catch yourself writing `[text](path.md)` for a vault note, convert it.
- **`private: false` by default.** Dumps can contain client/NDA material or half-formed thoughts — flip to `true` if this dump shouldn't reach teammates. The sync layer honors the flag.

## Process

1. `mkdir -p "$AGENT_HOME/context"`.
2. Identify the bd-id: from `$ARGUMENTS`, the plan file in conversation, or ask. If the dump isn't tied to a beads issue (e.g. exploratory research), set `bd: none` and skip steps 7 and 10.
3. Compute filename and confirm no collision.
4. Resolve parent for frontmatter: `bd dep list <id> --direction=down --type parent-child --json` → first `id` (empty if none, or if `bd: none`).
5. Read `$CLAUDE_SESSION_ID` (set by SessionStart hook). If empty, set `sessions: []`.
6. Walk back through the conversation and fill each section, wikilinking files / concepts / tickets / prior notes.
7. **Plan sweep** (skip if `bd: none`): locate `$AGENT_HOME/plan/<bd-id>-*.md`. For each `- [ ]` line whose step is clearly done per the conversation, flip it to `- [x]` (and append `→ <one-line divergence>` if the implementation diverged in a small, captureable way — see "Plan mutation" rules above). Do not touch any other text in the plan. Append `$CLAUDE_SESSION_ID` to the plan's `sessions:` list if not already present.
8. Write the context file with `kind: agent-note`, the resolved `parent:` (empty if none), and `$CLAUDE_SESSION_ID` in `sessions:`.
9. Cross-link back to beads: `bd comment <bd-id> "context: $AGENT_HOME/context/<label>--<date>-<time>.md"` — makes the dump discoverable from `bd show`.
10. If any checkboxes were ticked in step 7, optionally `bd comment <bd-id> "checked (via dump): <one-line list>"` so the bd thread reflects progress (skip if you'd rather keep the comment thread quiet — the plan diff itself is a record).
11. Report the context file path and the count of ticked boxes (if any) to the user in one line.
