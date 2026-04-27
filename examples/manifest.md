---
type: manifest
aliases: [projects, resources]
tags: [manifest]
---

# Project manifest

Canonical reference for every project the agent system tracks. Skills (`/bdx:plan`, `/bdx:scope`, `/bdx:triage`) consult this file to validate labels, infer components, and enrich briefings.

Drop this file at `$AGENT_HOME/manifest.md` and edit it to taste. Skills don't write to it (apart from `/bdx:manifest`, which is opt-in and only ever appends or updates a single project's entry).

**Conventions:**
- One H2 per project.
- The H2 heading text is the **project slug** — exactly what goes in `bd -l <slug>`.
- `path`, `repo`, `type`, and `notes` are free-form but should stay accurate.
- `components` is required for monorepos, omitted for single-package projects.
- Component keys (e.g. `ui`, `api`) are also valid `bd -l <component>` labels — use kebab-case, single-word when possible.
- Don't create compound labels like `myrepo-ui` — that breaks the cross-repo component view (`bd list -l ui`).
- `aliases` lets `/bdx:plan` recognize alternate names you might use for the same project (e.g. shortened forms, old names).

---

## example-project

- **slug**: `example-project`
- **aliases**:
	- example1
	- ex-proj
- **path**: `~/src/github.com/your-org/example-project`
- **repo**: https://github.com/your-org/example-project
- **type**: monorepo
- **components**:
  - `ui` — `apps/ui/` — Vue 3 frontend
  - `api` — `apps/api/` — Nest backend
  - `docs` — `apps/docs/` — Astro docs site
- **notes**: anything skills should know — build system, deploy target, conventions, gotchas. Free-form.

---

## example-single-package

- **slug**: `example-single-package`
- **path**: `~/src/github.com/your-org/example-single-package`
- **repo**: git@github.com:your-org/example-single-package.git
- **type**: single-package
- **notes**: For single-package projects, omit the `components:` block — the project label alone is enough.
