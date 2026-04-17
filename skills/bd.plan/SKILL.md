---
name: bd.plan
description: Create a beads issue and write a structured plan to $AGENT_HOME/plan that doubles as the execution prompt. Cross-links bd issue ↔ plan file.
user-invocable: true
argument-hint: optional-title-or-slug
---

Persist the plan that's been discussed in this conversation as an **Obsidian-friendly, agent-executable plan** at `$AGENT_HOME/plan/`, and create the paired beads issue so state lives in `bd` and content lives in Obsidian. This is the **before** half of the bd.plan / bd.dump / bd.summarize triad.

This skill is the only way a plan enters the system — do not write plan files ad-hoc elsewhere.

## What this skill does (in order)

1. Draft a short title and kebab-case slug from the conversation or `$ARGUMENTS`.
2. Derive labels (see Labels section below).
3. Create the beads issue: `bd create "<title>" -t task -p <0-3> -l <project> [-l <component> ...]` and capture the returned `bd-xxx` ID.
4. Write the plan to `$AGENT_HOME/plan/bd-xxx-<slug>.md` (see template below).
5. Cross-link: `bd update bd-xxx -d "plan: $AGENT_HOME/plan/bd-xxx-<slug>.md"` so the beads issue points at the plan.
6. Report the bd-id, labels, and path back to the user in one line.

## Labels

Every issue gets a **project label** (required) and zero or more **component labels** (optional). The primary label is always the repo name so `bd list -l <repo>` gives the unified per-project queue.

### Project label (required)

Auto-derive from the git root:

```
basename "$(git rev-parse --show-toplevel 2>/dev/null)"
```

- If the command succeeds, cross-check the result against the manifest. Match against **H2 slug first, then `aliases:` entries** for each project. If either matches, use the canonical slug (the H2) as the label. If neither matches, warn the user: "This repo isn't in the manifest — add an entry, add this name as an alias, or confirm the label." Use the derived name on confirmation.
- If the command fails (not in a git repo, e.g. working from `~/.claude` or a sandbox), read `$AGENT_HOME/manifest.md`, present the known project slugs as a numbered list, and ask the user to pick one. Do not guess.
- The user may refer to a project by any alias during conversation; always resolve to the canonical slug before passing to `bd -l`.

### Component labels (optional)

Only add when the task is clearly scoped to a subcomponent of a larger repo (monorepo case). The authoritative list of valid component labels for a given project lives in `$AGENT_HOME/manifest.md` under that project's `components:` field. Only apply components that are declared in the manifest for this project — do not invent new component names.

Derive from:

- Paths mentioned in the conversation that match a manifest component's path (e.g. plan touches `apps/ui/*` and the manifest declares `ui — apps/ui/` → label `ui`)
- Explicit user cue ("this is an API task") mapped against declared components
- `$ARGUMENTS` if the user passed a component name — validate against the manifest

If the scope is cross-cutting (touches multiple components), skip component labels — the project label alone suffices.

### Never do this

- Don't create compound labels like `listscrub-ui` — that breaks the cross-repo component queries (`bd list -l ui`).
- Don't add labels speculatively. A label should answer a real query someone would run.

## Output location

Write to: `$AGENT_HOME/plan/<bd-id>-<slug>.md`

Naming convention:
- **The bd-id prefix is mandatory** — every plan is keyed by its beads issue. One plan per bd-id; grep the bd-id to find every related file in the vault.
- `<slug>`: short, kebab-case, lowercase, no spaces — describes *what's being built* (e.g. `auth-middleware-rewrite`). Derive from `$ARGUMENTS` if provided, otherwise from the conversation topic.
- **No date in the filename.** Unlike summaries/context dumps, there is one plan per bd-id. The bd-id itself is the uniqueness token.
- Create `plan/` if it doesn't exist.
- **Never rename after creation** — Obsidian wikilinks point at the filename. Use Obsidian's rename if truly needed.

## Priority guidance for `bd create -p`

- `-p 0` — urgent / blocking real work
- `-p 1` — important, this week
- `-p 2` — normal backlog (default)
- `-p 3` — someday / nice-to-have

If the user didn't signal urgency, use `-p 2`.

## Linking rules (critical for Obsidian graph view)

- **All in-vault references are wikilinks**: `[[note-name]]` or `[[note-name|display]]`. Never use `[text](path.md)` for anything inside `$AGENT_HOME`.
- **Link touched source files as wikilinks** — e.g. `` `[[src/auth/middleware.ts]]` `` (wrap in backticks when it should also render as code in prose).
- **Link concepts** as `[[concept/<idea>]]` so repeated ideas become hub nodes.
- **Link tickets / PRs / related bd issues** as `[[INGEST-482]]`, `[[PR-1234]]`, `[[bd-xxx]]`.
- **Link related vault notes**: `[[summary/<slug>--<date>]]`, `[[context/<label>--<date>-<time>]]`, sibling plans `[[plan/bd-yyy-<slug>]]`.
- **Frontmatter `bd:`** — this is the canonical link back to beads state.
- **Frontmatter `tags:`** — always include `plan` and the project/area.
- External URLs stay as plain markdown links.

## File structure

```markdown
---
bd: bd-xxx
title: <human-readable title>
created: <YYYY-MM-DD>
aliases: []
tags: [plan, <project-or-area>]
private: false   # true = personal/side-project, skip team sync
status: draft   # agents flip to in-progress / done via bd, not here
sessions:
  - <uuid-of-session-that-wrote-this>   # from $CLAUDE_SESSION_ID
---

# <title>

> Beads: `bd-xxx` · State lives in beads (`bd show bd-xxx`), not this file.

## Goal
<1–2 sentences on what we're building and why. Inline-link concepts as [[concept/...]].>

## Context
<what led to this, constraints, tickets like [[INGEST-482]], related notes [[summary/...]] / [[context/...]]>

## Scope

### In scope
- <bullet per outcome, not per task>

### Out of scope
- <explicit non-goals — preempt scope creep>

## Plan

### Phase 1 — <name>
- [ ] <specific, verifiable step> — touches `[[<file-path>]]`
- [ ] ...

### Phase 2 — <name>
- [ ] ...

<Use as many phases as needed. Each checkbox should be verifiable — the agent flips it when done.>

## Key decisions (already made)
- **<decision>** — <rationale>. Decided by: <agent | user | both>. Related: [[concept/<idea>]]
- ...

## Open questions
- <question with the options being weighed, link concepts>
- ...

## Verification
<How we'll know this is done — tests, manual checks, acceptance criteria.>

## Related
- [[bd-yyy]] — <relationship>
- [[summary/<prior-slug>--<date>]]
- [[concept/<hub-idea>]]
```

## Rules

- **The plan is the prompt.** Write it so an agent can pick it up cold and execute — no "see our chat" references. Self-contained.
- **Checkboxes are verifiable steps, not vibes.** "Refactor auth" is not a checkbox. "Extract `requireAuth` middleware into `src/auth/middleware.ts`" is.
- **Capture decisions already made, separately from open questions.** Future-you needs to distinguish "settled" from "pending."
- **Don't bloat.** A plan is a handoff, not a design doc. If a section is empty, omit it — don't leave stub "TBD" lines.
- **Every cross-reference is a wikilink.** If you catch yourself writing `[text](path.md)` for a vault note, convert it.
- **One plan per bd-id.** If the task's shape has fundamentally changed, close the old bd and `bd.plan` a new one rather than rewriting history.
- **`private: false` by default.** Flip to `true` for side-project/personal plans that shouldn't sync to teammates. The sync layer (not this skill) honors the flag — the skill just writes it.

## Process

1. `mkdir -p "$AGENT_HOME/plan"`.
2. Derive title + slug from `$ARGUMENTS` or conversation.
3. Derive labels: project from `basename "$(git rev-parse --show-toplevel 2>/dev/null)"`; ask if not in a repo. Derive any component labels from conversation/paths.
4. `bd create "<title>" -t task -p <0-3> -l <project> [-l <component> ...]` — capture `bd-xxx` from output.
5. Read `$CLAUDE_SESSION_ID` — set by the `SessionStart` hook. If empty (e.g. running in `--print` mode where the hook doesn't fire), set `sessions: []` and continue.
6. Write `$AGENT_HOME/plan/bd-xxx-<slug>.md` using the template above. Include `$CLAUDE_SESSION_ID` in `sessions:` list and the labels in `tags:`.
7. `bd update bd-xxx -d "plan: $AGENT_HOME/plan/bd-xxx-<slug>.md"` to cross-link.
8. Report the bd-id, labels, and absolute plan path back to the user in one line.

## Resuming

To re-enter the session that produced this plan: `claude --resume <uuid>`. The `sessions:` frontmatter lists every session that touched the artifact, newest last.
