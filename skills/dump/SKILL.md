---
name: dump
description: Dump all relevant and important context from the current conversation into $AGENT_HOME/context so it can be reloaded later.
user-invocable: true
argument-hint: optional-label
---

Dump the important context of this conversation to `$AGENT_HOME/context/` as an **Obsidian-friendly note**. The user opens these in Obsidian and relies on graph view to see how context dumps connect to summaries, plans, files, concepts, and tickets — so every cross-reference must be a wikilink (`[[...]]`).

This is a broader, lossier snapshot than `summarize` — it captures conversational state (what the user wants, what's been tried, what's pending) rather than a clean post-implementation writeup.

## Output location

Write to: `$AGENT_HOME/context/<label>--<YYYY-MM-DD>-<HHMM>.md`

Naming convention:
- `<label>`: short, kebab-case, lowercase, no spaces — describes the *session topic* (e.g. `debugging-ingest-backpressure`). Derived from `$ARGUMENTS` if provided.
- `--` (double dash) separates the label from the timestamp so labels containing numbers/dates stay unambiguous.
- `<YYYY-MM-DD>-<HHMM>`: ISO date plus 24h local time, zero-padded (e.g. `2026-04-16-1430`). Context dumps happen multiple times per day, so the time is mandatory.
- Create `context/` if it doesn't exist.
- **On the rare collision** (same label + same minute): append `-2`, `-3`. Better: pick a more specific label.
- **Never rename after creation** — Obsidian wikilinks point at the filename. If truly needed, use Obsidian's rename (which updates backlinks).

## Linking rules (critical for Obsidian graph view)

- **All in-vault references are wikilinks**: `[[note-name]]` or `[[note-name|display]]`. Never use `[text](path.md)` for anything inside `$AGENT_HOME`.
- **Link files as wikilinks** — e.g. ``[[src/jobs/ingest.ts]]``. Unresolved wikilinks still appear in the graph and cluster by name, which is what we want.
- **Link concepts** as `[[concept/<idea>]]` (e.g. `[[concept/backpressure]]`, `[[concept/rbac]]`) so repeated ideas become hub nodes.
- **Link tickets / PRs** as `[[INGEST-482]]`, `[[PR-1234]]`.
- **Link related summaries or prior dumps** as `[[summary/<slug>--<YYYY-MM-DD>]]` or `[[context/<label>--<YYYY-MM-DD>-<HHMM>]]` — this is what lets graph view show trails across sessions.
- **Frontmatter `tags:`** — always include `context` plus the project/area tag, so graph view can color-filter.
- **Frontmatter `aliases:`** — add alternate names for the session topic so other notes resolve to this dump.
- External URLs (non-vault) stay as plain markdown links — those aren't part of the graph.

## File structure

```markdown
---
bd: bd-xxx   # or "none" if this dump isn't tied to a specific beads issue
label: <label>
dumped_at: <ISO timestamp>
cwd: <current working directory>
aliases: []
tags: [context, <project-or-area>]
private: false   # true = personal/side-project, skip team sync
sessions:
  - <uuid-of-session-producing-this-dump>   # from $CLAUDE_SESSION_ID
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

- **Prefer signal over volume.** Skip chitchat, resolved detours, and anything trivially re-derivable from the repo.
- **Preserve verbatim what matters verbatim.** Exact error messages, exact user phrasing on preferences, exact command outputs — paste these, don't paraphrase.
- **Don't invent.** If you don't know a section's answer, write "unknown" or omit. Never guess.
- **Don't duplicate `summarize`.** If the work is done and clean, prefer `summarize`. Use `dump` mid-flight or when work is messy/incomplete.
- **Capture constraints, not just content.** "User hates emoji in code", "must stay on Node 18", "can't touch auth without review" — these are load-bearing.
- **Include cwd and timestamp** so the dump is interpretable out of context.
- **Every cross-reference is a wikilink.** If you catch yourself writing `[text](path.md)` for a vault note, convert it.
- **`private: false` by default.** Dumps can contain client/NDA material or half-formed thoughts — flip to `true` if this dump shouldn't reach teammates. The sync layer honors the flag.

## Process

1. `mkdir -p "$AGENT_HOME/context"`.
2. Identify the bd-id: from `$ARGUMENTS`, the plan file in conversation, or ask. If the dump isn't tied to a beads issue (e.g. exploratory research), set `bd: none` and skip step 7.
3. Compute filename and confirm no collision.
4. Read `$CLAUDE_SESSION_ID` (set by SessionStart hook). If empty, set `sessions: []`.
5. Walk back through the conversation and fill each section, wikilinking files / concepts / tickets / prior notes.
6. Write the file with `$CLAUDE_SESSION_ID` in `sessions:`.
7. Cross-link back to beads: `bd comment <bd-id> "context: $AGENT_HOME/context/<label>--<date>-<time>.md"` — makes the dump discoverable from `bd show`.
8. Report the path back to the user in one line.
