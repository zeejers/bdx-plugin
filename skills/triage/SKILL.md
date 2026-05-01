---
name: triage
description: Drain the inbox and unscoped bd queues — for each item, decide whether to merge into an existing task or seed a new one (via plan or scope). Use periodically (start of day, between tasks, when the inbox is piling up) to clear capture into structured state. Skip for one-off conversions of a single item (use scope on the bd-id, or plan to convert one inbox note manually). Triage never starts execution — output is always tasks ready for a later attach. Predecessor: phone capture / `bd create` shorthand. Successor: plan or scope.
user-invocable: true
argument-hint: "optional — 'inbox' | 'bd' | <filename> | <bd-id>"
---

Turn mobile-captured work (inbox markdown or bare `bd create` items) into real task state. By default, drains **both** sources: for each item, append to an existing bd issue (if there's a clear active workstream) or seed a new task via `plan` / `scope`. Output is always tasks ready to be picked up later via `attach` — triage never starts execution.

**Trigger**: the capture queue (inbox files + unscoped bds) needs draining. **Skip** for one-off conversions — use `scope` directly on a single bd-id, or `plan` to convert one inbox note by hand.

## Sources

Triage draws from two independent queues:

1. **Inbox** — files in `$AGENT_HOME/inbox/`. Created by the phone capture flow. Content is free-form markdown; the file itself gets deleted on success.
2. **Unscoped bd** — `bd list --no-labels -s open,in_progress --no-pager` (plus stale `--empty-description` filter if applicable). Items created directly via `bd create` that never went through `plan`, so they have no project label. The bd issue is preserved across triage — we add labels / scope it, never delete.

## Modes (argument grammar)

Arguments disambiguate by shape:

| `$ARGUMENTS` | Mode |
|---|---|
| (empty) | drain **both** sources (default) |
| `inbox` | inbox files only |
| `bd` | unscoped bd issues only |
| `<filename>` (exists in inbox dir) | single inbox file |
| `bd-<id>` (matches `bd-[a-z0-9]+`) | single unscoped bd issue |

Parse order: literal keyword → bd-id regex → filename lookup → otherwise error.

## What this skill does (per item)

0. **Load the manifest** once at the start of the run: read `$AGENT_HOME/manifest.md`, build an in-memory map of `slug → {path, components[], aliases[]}`. Also build a reverse index `alias → slug`. Authoritative list of valid labels.
1. **Read the item.**
   - Inbox file: read the file, extract core intent in 1–2 sentences.
   - Unscoped bd: `bd show <id>`, use title + description as the content surface.
   Match content against manifest slugs, aliases, and component names to derive label candidates. Always store canonical slugs (never aliases) as labels. Build search keywords.
2. **Search for existing matches.** `bd search "<keywords>"` + `bd list -l <project> -s open,in_progress,blocked` for the active queue. Look at top 5 candidates by relevance. Exclude the item itself from candidates when triaging a bd (don't match it to itself).
3. **Decide attach vs create/scope:**
   - **Unambiguous match** (same bug, obvious continuation, high similarity) → attach silently.
   - **Unambiguous new** (no relevant candidates, novel topic) → create/scope silently.
   - **Ambiguous** (plausible match but not certain) → defer to the ambiguous queue (see below); do NOT guess.
4. **Execute the decision** (for unambiguous items). Action differs by source:

   | Decision | Inbox source | Unscoped bd source |
   |---|---|---|
   | **Attach** | `bd comment <target> "inbox: <verbatim content>"` | `bd comment <target> "merged from bd-xxx: <title> — <body>"`, then `bd supersede bd-xxx --with=<target>` |
   | **Create/Scope** | run `plan` with the inbox content as the seed (derives labels, priority `-p 2` default, status `open`) | run `scope bd-xxx` (adds labels, writes plan file, preserves original description inside plan Context) |
   | **Cleanup** | `rm` inbox file after success | nothing — the bd stays, now scoped |

   If attaching an inbox note changes scope of the target, add a second comment flagging "plan may need update".
5. **Log** the action (one line per item) for the final report. For inbox attaches/creates, only delete the file after the bd operation succeeded.

## Handling ambiguous items

After the silent pass, surface ambiguous items to the user as a single batch at the end:

```
3 items need a decision:

1. inbox: "fix five9 timeout on large list imports" — possibly related to bd-83p (listscrub list import bug)
   [a]ttach to bd-83p / [c]reate new / [s]kip for now

2. bd-abc: "dashboard layout broken" — possibly related to bd-77x (dashboard refactor)
   [a]ttach to bd-77x / [s]cope as own task / [k]skip for now

3. ...
```

User answers per-item; process their choices. Skipped items stay in place (inbox file untouched; bd stays unscoped).

Note the label difference per source: inbox items use [c]reate, bd items use [s]cope (mnemonic for `scope`). Both mean "this item becomes its own task." For bd items, [k]skip is used instead of [s]kip to avoid colliding with scope.

## Final report

At the end of a run, print a compact summary broken out by source:

```
Triaged 11 items — 7 scoped/created, 3 attached, 1 skipped.

Inbox (5):
  created  bd-abc  "refactor auth middleware"       (listscrub, api)
  created  bd-def  "dark mode for dashboard"        (listscrub, ui)
  attached bd-83p  "+inbox comment re: five9 timeout"

Unscoped bd (6):
  scoped   bd-ghi  "fix login regression"           (workflows, api)
  scoped   bd-jkl  "add export button"              (quickforms, vue)
  attached bd-mno  "merged into bd-77x (dashboard refactor)"

Skipped:
  inbox/wait-for-decision.md
  bd-pqr  "needs more context before scoping"
```

## Rules

- **Never start executing work.** Triage converts capture to task; that's it. Items stay in `open` (new/scoped) or `in_progress` (attach of inbox) — execution is a separate deliberate act via `attach`.
- **Never rewrite an existing plan.** When attaching, the note goes into a `bd comment`, not into the plan file. When scoping, `scope` guards against existing plans.
- **Err toward creating/scoping on auto-decisions.** A lossy capture merged into the wrong task is worse than a slight duplication. If the match isn't clearly the same workstream, treat the item as ambiguous and surface it.
- **Silent pass first, then surface ambiguities.** Users skimming the final report want to see *what was done*, not N interactive prompts. Batch the asks at the end.
- **Don't auto-delete inbox files if anything failed.** Only `rm` after the bd operation succeeded. A failed triage on one item should not stop the others; log and continue.
- **For bd sources, never modify the issue until a decision is executed.** Don't update labels or status during the silent pass until we know the decision — attaches use `bd supersede`, scopes use `scope`.
- **Skipped items stay.** Inbox files untouched; bd items remain unscoped. They'll come up again on the next triage run.

## Process

1. **Parse `$ARGUMENTS`** to determine mode:
   - empty → both sources
   - `inbox` → inbox only
   - `bd` → unscoped bd only
   - looks like bd-id (`bd-[a-z0-9]+`) → single bd item
   - looks like filename that exists in `$AGENT_HOME/inbox/` → single inbox file
   - otherwise → error with usage hint.

2. **Build the worklist**:
   - Inbox source: `ls $AGENT_HOME/inbox/` sorted by `mtime` oldest-first (or the single filename).
   - Unscoped bd source: `bd list --no-labels -s open,in_progress --no-pager` (or the single `bd show <id>`).
   - If combined mode, concatenate with inbox first (capture order), then bd (typically fewer). Preserve source identity per item.
   - If empty, print "Nothing to triage" and stop.

3. **Silent pass**: for each item, read content, extract intent + keywords, search bd, classify as `attach-clear`, `new-clear`, or `ambiguous`. For the two clear buckets, execute immediately and clean up. Track failures to report — don't abort the batch.

4. **Ambiguous pass**: present ambiguous items as a numbered list with candidate matches. Ask for per-item decisions in one round. Apply the decisions.

5. **Report**: print the compact summary with source breakdown (created, scoped, attached, skipped, failed).
