# Examples

Drop-in starter content for `$AGENT_HOME/`. Copy what you need, edit to taste.

## Manifest

[`manifest.md`](./manifest.md) — sample project manifest. Place at `$AGENT_HOME/manifest.md`. Read by `/bdx:plan`, `/bdx:scope`, `/bdx:triage` to validate project + component labels and pick the right slug for monorepos.

```bash
mkdir -p "$AGENT_HOME"
cp examples/manifest.md "$AGENT_HOME/manifest.md"
# then edit it to list your real projects
```

The plugin works without a manifest — `/bdx:plan` will warn once per unknown repo and proceed with the derived name. Component labels in monorepos require it though.

## Personas

[`personas/`](./personas/) — example reviewer voices used by `/bdx:summarize` (and invokable directly via `/bdx:persona`). Place files at `$AGENT_HOME/personas/<slug>.md`.

```bash
mkdir -p "$AGENT_HOME/personas"
cp examples/personas/*.md "$AGENT_HOME/personas/"
```

Personas are fully optional. With none installed, `/bdx:summarize` simply omits the `## Persona reviews` section — no error, no nag.

Included examples:
- [`linus.md`](./personas/linus.md) — Linus Torvalds. Code-quality / data-structure / API-design lens.
- [`dhh.md`](./personas/dhh.md) — David Heinemeier Hansson. Architecture / over-abstraction / dependency-sprawl lens.

Adapt them, replace them, or write your own. The frontmatter contract is small (`name:`, `description:` with a "Use when ..." phrase that `auto` mode matches against). Body is freeform prose — see the included examples for shape.

## Obsidian Base (cross-artifact view)

[`bdx-artifacts.base`](./bdx-artifacts.base) — an [Obsidian Base](https://help.obsidian.md/bases) that filters every bdx-generated note (`kind: agent-note`) into table views: all artifacts, plans grouped by parent epic, plans without a parent, and recent activity. Place at the root of your vault (e.g. `$AGENT_HOME/bdx-artifacts.base`).

```bash
cp examples/bdx-artifacts.base "$AGENT_HOME/bdx-artifacts.base"
```

Open it in Obsidian to see how `parent:` rolls phase plans up under their epic, and how `kind: agent-note` lets you filter the bdx layer out from the rest of your vault. If you don't use the views, the metadata isn't earning its keep — feel free to delete the file and skip writing those frontmatter fields going forward.

Requires Obsidian 1.9+ (Bases feature). Older Obsidian: ignore — the frontmatter fields are still useful for `dataview` if you prefer.
