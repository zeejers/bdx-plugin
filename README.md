# bdx

> **Couples bd tasks to a durable markdown notebook at every lifecycle event (create → attach → dump → summarize → close). `bd` is the source of truth for task state; markdown is the narrative record.**

Claude Code plugin for the [`bd` (beads)](https://github.com/gastownhall/beads) issue tracker. Turns bd into a session-aware task system: every task is born with a plan file, every session resuming a task gets pre-loaded with full context, and nothing closes without a written summary.

## Why I built this

I wanted to see what my agents were working on through beads, but I also wanted everything they were thinking — plans, mid-stream context, final summaries — persisted to disk, not locked inside ephemeral Claude sessions.

The thing I care about most is **drift**. What did the plan say at the start, what did the implementation actually become, what decisions got made along the way and why? When you're pairing with an agent, those details evaporate the moment the session ends. Without a markdown record, you have the code and nothing else — no rationale, no alternatives considered, no "we tried X but backed out because Y."

I also wanted to close sessions **without fear**. A running session holds a lot of working memory; dumping it to disk first means I can end cleanly and pick up later from the notebook, not from scratch.

Everything lives as markdown with `bd-<id>` frontmatter and wikilink cross-references, which means you get [Obsidian graph view](https://help.obsidian.md/Plugins/Graph+view) for free — plans, summaries, and context dumps all show up as nodes, and over time you can see how tasks, decisions, and knowledge correlate across projects.

## What's in the box

### Skills (`/bdx:<name>`)
- `plan` — create a bd issue + structured plan file
- `attach` — resume an existing bd task, load plan/context/summary into the session
- `dump` — mid-flight context snapshot (reloadable later)
- `summarize` — post-implementation writeup to `$AGENT_HOME/summary/`
- `close` — finalize a task (writes summary if missing, then closes with resolution)
- `label` — apply plain labels or namespaced external refs (`jira:ABC-123`, `linear:FOO-456`)
- `scope` — add project + component labels to an existing unscoped bd + write its plan
- `triage` — drain inbox / unscoped bd issues into real tasks
- `manifest` — inspect a project on disk and add/update its `$AGENT_HOME/manifest.md` entry

### Hooks
- **`SessionStart` (startup + resume)** → `capture-session-id.sh`
  Exposes the session UUID as `$CLAUDE_SESSION_ID` to all downstream tool calls, so `/bdx:plan`, `/bdx:dump`, and `/bdx:summarize` can record which session produced each artifact in the plan's `sessions:` frontmatter. Enables `claude --resume <uuid>` workflows.
- **`SessionStart` (startup + resume)** → `bdx-ensure-agent-home.sh`
  Resolves `$AGENT_HOME` (default `~/.bdx-agent`), auto-creates the `plan/`, `context/`, `summary/`, `inbox/` subdirs, and exports the value so every subsequent tool call in the session sees it.
- **`SessionStart:startup`** → `bd-auto-attach.sh`
  If `$BD_ID` is set in the parent env, auto-loads the plan/context/summary, appends the session UUID to the plan's `sessions:` frontmatter, flips bd status `open → in_progress`, and emits the bundle as `additionalContext` on turn 1.
- **`PreToolUse:Bash`** → `block-bare-bd-close.sh`
  Blocks direct `bd close` (and `bd update --status closed`) so you're forced through `/bdx:close`, which writes a summary first.

### Launcher
- `scripts/bdc` — `bdc <bd-id>` sets `BD_ID`, derives a slug from the bd title, and runs `claude -n "<bd-id>-<slug>"`. Symlink to `~/bin/bdc` or alias it.

## Prerequisites

- `bd` (beads) CLI on `$PATH` — [gastownhall/beads](https://github.com/gastownhall/beads)
- `jq`, `python3` on `$PATH` (used by the auto-attach hook)

## `$AGENT_HOME`

Durable markdown (plans, context dumps, summaries, inbox) lives under `$AGENT_HOME`. The plugin defaults to `~/.bdx-agent/` and auto-creates the subdir layout on first run:

```
$AGENT_HOME/
├── plan/       # long-form plans (created by /bdx:plan, also the execution prompt)
├── context/    # mid-stream state dumps (/bdx:dump)
├── summary/    # post-implementation writeups (/bdx:summarize, /bdx:close)
└── inbox/      # mobile-capture seeds, triaged by /bdx:triage
```

**Override** by exporting `AGENT_HOME` in your shell rc before launching `claude`:

```bash
# e.g. use a Dropbox/iCloud path so plans sync across machines
export AGENT_HOME="$HOME/Dropbox/Notes/agent"
```

The plugin hook respects whatever's set and only falls back to `~/.bdx-agent` when unset.

## Install

**Local dev** (symlink approach, easiest to iterate):
```bash
claude --plugin-dir ~/src/github.com/bdx-plugin
```

**Via marketplace** (once published):
```bash
claude plugin install bdx@<marketplace>
```

## Usage

Start a session attached to a bd task:
```bash
bdc bd-abc         # runs: BD_ID=bd-abc claude -n "bd-abc-<slug>"
```

Close a task (writes summary, then closes):
```
/bdx:close bd-abc
```

Override for the rare raw close:
```bash
QF_ALLOW_BARE_BD_CLOSE=1 bd close bd-abc
```

## Escape hatches

- `BD_ID` unset → SessionStart hook is a silent no-op; normal `claude` invocations are unaffected
- `QF_ALLOW_BARE_BD_CLOSE=1` → bypass the `bd close` guard for one command
