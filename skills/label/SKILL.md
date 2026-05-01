---
name: label
description: Apply plain labels or namespaced external refs (jira:..., linear:..., gh:..., figma:...) to a bd issue, and propagate namespaced refs into the linked plan's frontmatter + Obsidian wikilinks. Use to wire a bd into outside-world tracking (Jira ticket, GitHub issue, Figma file) or to add ad-hoc tags. Skip for project/component labels (those belong on plan/scope at task creation, not after) and for parent-child relationships (use `bd dep add <child> <parent> -t parent-child` directly so frontmatter re-derives correctly). Contexts/summaries are left as historical snapshots.
user-invocable: true
argument-hint: bd-id <label-or-ref> [<label-or-ref> ...]
---

Add labels or external references to an existing bd issue and sync the plan markdown so Obsidian graph view picks up the links. Supports two kinds of labels:

- **Plain labels** — e.g. `priority-high`, `needs-design`, `blocked-by-legal`. Go on the bd issue only.
- **Namespaced external references** — any label containing `:` is treated as an external ref, e.g. `jira:ZAP-50`, `linear:FOO-123`, `gh:listscrub/platform#412`, `figma:<file-id>`. These go on the bd issue AND into the plan's `external:` frontmatter, plus a wikilink in the plan's Related section for Obsidian graph view.

## What this skill does (in order)

1. **Parse `$ARGUMENTS`**: first token is the bd-id; remaining tokens are labels/refs. If the bd-id is missing, ask. If no labels/refs given, ask.
2. **Validate the bd exists**: `bd show <bd-id>`. If missing, abort.
3. **Apply labels to bd**: for each label, `bd label add <bd-id> <label>`. Idempotent — re-adding an existing label is a no-op. Skip silently if already applied.
4. **Split labels**: separate namespaced refs (contain `:`) from plain labels.
5. **If namespaced refs and the bd has a plan**:
   - Locate the plan: `ls $AGENT_HOME/plan/<bd-id>-*.md`.
   - If found, read its frontmatter. Add any new refs to an `external:` list (create the key if missing, dedupe entries).
   - In the plan body, ensure a `## Related` section exists and contains a wikilink per ref. Use the ref's non-namespace portion for the wikilink label: `jira:ZAP-50` → `[[ZAP-50]]`, `gh:listscrub/platform#412` → `[[listscrub#412]]`. Dedupe — don't add a wikilink that's already there.
   - If no plan file exists (task was created without `plan`), skip the markdown update silently. Bd labels are enough.
6. **Do not touch contexts or summaries.** They're historical snapshots. A ref added later doesn't belong in a record of the past.
7. **Report** one line per label applied, then one line per file modified: `Linked bd-le4 to jira:ZAP-50, priority-high — plan updated.`

## Rules

- **Labels are case-sensitive** — treat `jira:ZAP-50` and `JIRA:zap-50` as different. Preserve the user's casing.
- **Idempotent.** Running the skill twice with the same args is safe — no duplicate labels, no duplicate wikilinks, no duplicate entries in `external:`.
- **Never remove labels.** Removal is a separate concern; use `bd label remove <id> <label>` and hand-edit the plan if you need to prune.
- **Never touch contexts or summaries.** Historical artifacts stay as written.
- **Preserve all other frontmatter.** When editing the plan's frontmatter, only touch `external:`. Every other key — `bd:`, `title:`, `created:`, `aliases:`, `tags:`, `private:`, `status:`, `sessions:`, anything user-added — must round-trip untouched.
- **Don't invent external systems.** The namespace prefix (`jira`, `linear`, `gh`, `figma`, etc.) is whatever the user provides. Don't try to normalize or autocorrect.
- **Plan missing is fine.** If a bd has no plan, this skill only updates bd labels. Don't create a plan just to link a ref.

## Wikilink derivation

For the `## Related` section in the plan body:

- `jira:ZAP-50` → `[[ZAP-50]]`
- `linear:FOO-123` → `[[FOO-123]]`
- `gh:listscrub/platform#412` → `[[listscrub#412]]` (use repo name + issue number)
- `figma:<long-id>` → `[[figma/<long-id>]]` (use namespace path form for things without a short human name)
- Anything ambiguous → use the full label verbatim: `[[<namespace>:<id>]]`

## Process

1. Parse bd-id and labels from `$ARGUMENTS`.
2. `bd show <bd-id>` to validate the issue exists and to get the current label set.
3. For each label: `bd label add <bd-id> <label>` unless already present.
4. For namespaced refs, locate the plan at `$AGENT_HOME/plan/<bd-id>-*.md`. If present:
   a. Read frontmatter; add refs to `external:` (create list, dedupe).
   b. Ensure `## Related` section exists in the body; add a wikilink per ref (dedupe).
   c. Write the file.
5. Print the one-line report.
