---
name: bd.manifest
description: Inspect a project on disk and add (or update) its entry in $AGENT_HOME/manifest.md. Infers slug, path, repo, type, components, and notes from the filesystem and git metadata.
user-invocable: true
argument-hint: optional-project-path (defaults to cwd)
---

Save manual manifest-editing work. Point this skill at a project directory; it inspects the filesystem + git to compose a manifest entry, shows you a diff, and (on your confirmation) appends or updates `$AGENT_HOME/manifest.md`.

The **only** field the skill cannot infer is `aliases` — it'll ask you directly.

## What this skill does (in order)

1. **Resolve the project root.**
   - If `$ARGUMENTS` is a path → use it.
   - Else → use cwd, then `git rev-parse --show-toplevel` to jump to the repo root.
   - If not in a git repo and `$ARGUMENTS` doesn't point to one, ask the user for a path. Do not guess.
2. **Inspect the filesystem** (read-only scan):
   - `git remote get-url origin` → repo URL (strip credentials if present)
   - Presence of: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `mix.exs`, `Gemfile`, `composer.json`, etc. → primary language/ecosystem
   - Monorepo markers: `pnpm-workspace.yaml`, `lerna.json`, `turbo.json`, `nx.json`, `rush.json`, root `package.json` with `workspaces`, `Cargo.toml` with `[workspace]`, `go.work`
   - If monorepo → list `apps/*/`, `packages/*/`, `services/*/`, `libs/*/` (whatever the workspace globs declare). For each, read its `package.json` name/description or `README.md` first line to compose a one-line component description. Component key = directory name (kebab-case).
   - `README.md` top paragraph → draft of `notes`
   - CI files (`.github/workflows/*`, `.circleci/*`, `fly.toml`, `vercel.json`, `Dockerfile`) → infer deploy target for notes
3. **Compose the entry.**
   - `slug` = basename of the project root (kebab-case, lowercased)
   - `path` = absolute path with `$HOME` rewritten to `~`
   - `repo` = git remote URL
   - `type` = `monorepo` if workspace markers present, else `single-package`
   - `components` = detected list (only for monorepos)
   - `notes` = concise synthesis: ecosystem + build tool + deploy target + anything load-bearing from README
   - `aliases` = empty list (ask user in next step)
4. **Ask for aliases.** Prompt: "Any alternate names you'd refer to this project as? (product name, internal nickname, old repo name). Comma-separated, or empty." Skip if user says none.
5. **Check for existing entry.** Grep for a matching H2 in `$AGENT_HOME/manifest.md`. Two cases:
   - **New**: append the composed entry (with a `---` separator line before it if the file's last content isn't already a separator).
   - **Update**: show a diff of existing vs. proposed; ask the user to confirm each changed field. On confirmation, replace the existing entry in place (preserve any fields the user edited by hand that weren't regenerated).
6. **Write the file.** Preserve surrounding entries verbatim — never reorder, never touch unrelated entries.
7. **Report** one line: `Added <slug>` or `Updated <slug> (fields: path, components)`.

## Rules

- **Never destroy hand-edits.** The manifest is user-editable. If updating, preserve fields the user has customized that the skill can't derive (e.g. `aliases`, tuned `notes`). When in doubt, show the diff and ask before overwriting.
- **Never scan outside the project root.** No `find` across `~/`. Stay within the given directory.
- **Don't invent components.** If the monorepo scan finds no component subdirs with recognizable packages, omit `components:` and set `type: single-package`.
- **Never write to anything other than `$AGENT_HOME/manifest.md`.** This skill is not allowed to mutate other files.
- **Don't `bd create` or touch beads state.** Manifest updates are independent of task state.

## Entry format (must match the manifest convention exactly)

```markdown
## <slug>

- **slug**: `<slug>`
- **path**: `<~-rewritten path>`
- **repo**: <url or "none">
- **type**: monorepo | single-package
- **components**:   # omit entire block if single-package
  - `<key>` — `<rel-path>/` — <one-line description>
- **aliases**: [<comma-separated>]   # omit if empty
- **notes**: <synthesis>
```

## Process

1. Resolve project root from `$ARGUMENTS` or cwd/git.
2. Inspect filesystem + git; draft the entry with inferred fields.
3. Ask the user for aliases.
4. Diff against existing manifest entry (if any); show to user.
5. Append or replace-in-place in `$AGENT_HOME/manifest.md`.
6. Print the one-line confirmation.
