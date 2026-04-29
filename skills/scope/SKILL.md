---
name: scope
description: Scope an existing unscoped bd issue — add project + component labels and write its plan file. For bd issues created directly (e.g. from phone) that never went through plan.
user-invocable: true
argument-hint: bd-id
---

Take an existing bd issue that lacks a project label and/or plan file, and bring it into the qf-managed system: add manifest-validated labels, write `$AGENT_HOME/plan/<bd-id>-<slug>.md`, cross-link. This is the "retarget `plan` at an existing bd" operation.

Used standalone (`/bdx:scope bd-xxx`) or called from `triage` when it decides an unscoped bd should become a real task.

## When to use

- A bd issue was created via `bd create` (phone, quick capture) without labels or plan
- An existing bd issue needs labels updated and a plan generated after the fact
- `triage` delegates here for the "scope" branch of its decision tree

**Do not use** on a bd that already has a plan file — in that case the plan is authoritative; edit it directly. Check for `plan:` in the bd's description or grep `$AGENT_HOME/plan/` for the bd-id before acting.

## What this skill does (in order)

1. **Resolve the bd-id** from `$ARGUMENTS`. Required — fail if missing.
2. **Read the existing bd**: `bd show <id>` to get title, description, existing labels, status, and priority (needed to seed the plan's `rank:` frontmatter).
3. **Guard**: if a plan file already exists at `$AGENT_HOME/plan/<bd-id>-*.md` or the description contains `plan: $AGENT_HOME/plan/`, abort with the existing path — do not overwrite.
4. **Derive slug** (kebab-case) from the bd title.
5. **Derive labels** (see Labels section below). Apply via `bd update <id> -l <project> [-l <component>...]`. bd labels are additive — existing labels are preserved.
6. **Read `$CLAUDE_SESSION_ID`** (set by SessionStart hook). If empty, use `sessions: []`.
7. **Write the plan file** at `$AGENT_HOME/plan/<bd-id>-<slug>.md` using the same template as `plan`. Seed Goal/Context from the bd's existing description.
8. **Cross-link**: `bd update <id> -d "plan: $AGENT_HOME/plan/<bd-id>-<slug>.md"` (replaces description — so preserve the original text inside the plan's Goal/Context first, not the bd body).
9. **Report** bd-id, labels added, plan path in one line.

## Labels

Same rules as `plan` — consult `$AGENT_HOME/manifest.md` as the authoritative list.

### Project label (required)

The bd issue didn't come from a git context, so we can't derive from `git rev-parse`. Strategy:

1. **Scan bd content for manifest signals**: match title + description against manifest slugs, `aliases:`, and component names. If exactly one project matches, use its canonical slug.
2. **If ambiguous or no match**: read `$AGENT_HOME/manifest.md`, present known project slugs as a numbered list, ask the user to pick. Do not guess.
3. **If user answered during `triage`**: accept the label passed in from the triage context rather than re-asking.

### Component labels (optional)

Only add when the bd's content clearly scopes to a subcomponent of the chosen project. Validate against the manifest's `components:` for that project. Do not invent components.

### Never do this

- Don't create compound labels like `listscrub-ui` — breaks cross-repo component queries.
- Don't overwrite existing labels; `bd update -l` is additive but never remove a user-applied label without asking.

## Plan file template

Identical to `plan`. Key seeding differences when scoping an existing bd:

- **Goal**: extract from the bd's title + description. Reword to 1–2 sentences if the description was a single-liner.
- **Context**: lead with "Originally captured as `bd-xxx` on `<created-date>`." then preserve the bd's original description body. Link any external refs found in the description.
- **Plan**: if the bd's description lists concrete steps, convert to checkboxes. Otherwise leave `Phase 1 — TBD` with a single checkbox asking the next session to flesh it out.
- **Frontmatter**: `status: draft`, `tags: [plan, <project>]`, `sessions: [$CLAUDE_SESSION_ID]`. Seed `rank:` (0-99) from the bd's existing priority captured in step 2 — p0→10, p1→30, p2→50, p3→70. If priority is unset, default rank to 50.

## Rules

- **Idempotent**: running twice on the same bd is a no-op (guard in step 3 catches it).
- **No status change**: scoping does not set `in_progress`. The bd stays in whatever status it was in (usually `open`). `attach` is the skill that flips to `in_progress`.
- **Preserve the original description inside the plan before overwriting with the plan pointer.** The `bd update -d` in step 8 replaces the description — if you don't copy the original into the plan's Context first, it's lost.
- **One plan per bd-id.** Same rule as `plan` — never rewrite the plan after creation.
- **Do not execute work.** Scoping just sets up the task for later pickup via `attach`.

## Process

1. Parse `$ARGUMENTS` → bd-id (must match `bd-[a-z0-9]+`). Abort if missing or malformed.
2. `bd show <id>` → capture title, description, labels, status.
3. Guard: if a plan already exists for this bd, print its path and abort.
4. Derive slug from title (kebab-case, lowercase, drop stopwords).
5. Derive project label (manifest scan → user pick if ambiguous). Derive component labels if applicable.
6. `mkdir -p "$AGENT_HOME/plan"`.
7. Write `$AGENT_HOME/plan/<bd-id>-<slug>.md` — seed Goal/Context from the bd's existing description (don't lose it).
8. `bd update <id> -l <project> [-l <component>...]` — add labels.
9. `bd update <id> -d "plan: $AGENT_HOME/plan/<bd-id>-<slug>.md"` — cross-link.
10. Print one-line report: `bd-id labels=[...] plan=<path>`.
