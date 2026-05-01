# bdx

**TL;DR** — every Claude Code session writes a markdown plan/summary keyed by `bd` issue. The session ends; the record stays.

> **Couples bd tasks to a durable markdown notebook at every lifecycle event (create → attach → dump → summarize → close). `bd` is the source of truth for task state; markdown is the narrative record.**

![Claude Code](https://img.shields.io/badge/Claude_Code-plugin-D97757?logo=anthropic&logoColor=white) ![beads](https://img.shields.io/badge/beads-task_glue-9333EA) ![dolt](https://img.shields.io/badge/dolt-versioned_storage-1E40AF) ![status](https://img.shields.io/badge/status-experimental-yellow)

Claude Code plugin for the [`bd` (beads)](https://github.com/gastownhall/beads) issue tracker. Every task gets a plan file. Every session resuming a task pre-loads with full context. Nothing closes without a written summary.

## Quickstart

Bootstraps `bd`, `dolt`, and `BEADS_DIR` / `AGENT_HOME` in one shot. Safe to re-run; skips anything already installed.

```bash
curl -fsSL https://raw.githubusercontent.com/zeejers/bdx-plugin/refs/heads/development/scripts/install.sh | bash
```

Then install the Claude Code plugin:

```bash
claude plugin marketplace add zeejers/bdx-plugin && claude plugin install bdx@bdx-marketplace
```

Non-interactive variant + flags: see [Install the Claude Code plugin](#install-the-claude-code-plugin) below and `./scripts/install.sh --help`.

### Uninstall

Reverses everything except your shell profile (those exports stay until you remove them by hand). Destructive ops default to *no*; `--dry-run` previews.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/zeejers/bdx-plugin/refs/heads/development/scripts/uninstall.sh)
```

## Why this exists

A running agent session holds a lot of working memory — what the plan said, what got tried, what was rejected and why. The moment the session ends, all of that evaporates. You're left with the diff and nothing else.

bdx couples every `bd` task to durable markdown — plans, mid-stream context dumps, summaries — keyed by bd-id with frontmatter and wikilinks. Sessions resume with full context loaded; nothing closes without a written record. The markdown lives in `$AGENT_HOME` so [Obsidian graph view](https://help.obsidian.md/Plugins/Graph+view) shows how tasks, decisions, and knowledge correlate across projects.

## Lifecycle

The skills compose as a state machine — each one names what comes before and after, so picking the right skill at any moment is a glance at the diagram, not a guess.

```
        capture                                 work
   ┌──────────────┐                  ┌───────────────────────┐
   │ inbox / bare │   triage         │                       │
   │ bd create    │ ─────────► plan ─┤ attach ──► dump? ──┐  │
   └──────────────┘     │            │   ▲                │  │
                        │            │   │  resume cold   │  │
                        └─► scope ───┤   └────────────────┘  │
                                     │                       │
                                     │       work done       │
                                     └─► summarize ──► close │
                                                             │
                                            (terminal) ──────┘

  orthogonal:  label  ·  manifest  ·  persona
```

**Read it as**: capture lands in inbox files or bare `bd create` rows. `triage` drains the queue into real tasks, routing each item to `plan` (new) or `scope` (retrofit existing bd). Either way you end up with a bd issue + paired plan file. `attach` resumes a session against that bd and loads everything tagged with the bd-id. Mid-session, `dump` snapshots head-state so you can fearlessly close the tab; the next `attach` pulls the dump back in. When the work is actually done, `summarize` writes the durable record (with optional persona reviews); `close` finalizes by ensuring a summary exists and `bd close`-ing.

**Orthogonal skills** don't fit the lifecycle — they're tools you reach for when needed. `label` adds plain or external-ref labels (`jira:`, `linear:`, etc.). `manifest` registers a new project. `persona` invokes a saved reviewer voice.

### Skills (`/bdx:<name>`)

- `plan` — open a new bd task + paired plan file. *Use for non-trivial work; skip for one-line fixes or existing bds (use `scope`).*
- `scope` — retrofit an existing bd (no plan, no project label) into the lifecycle. *Predecessor: `triage` or bare `bd create`.*
- `attach` — resume an existing bd task in a fresh session: load plan + prior contexts/summaries, flip status to in_progress. *Predecessor: `plan` or `scope`. Successor: `dump` or `summarize`.*
- `dump` — snapshot session head-state to `$AGENT_HOME/context/` so you can log out fearlessly. *Trigger is leaving the session, not noting things — use a `bd comment` if you're still working.*
- `summarize` — write the durable post-implementation record to `$AGENT_HOME/summary/`, with optional persona reviews. *Predecessor: a finished work session. Successor: `close`.*
- `close` — finalize the task: ensure a summary exists, then `bd close` with a resolution. *Terminal — closes the lifecycle.*
- `triage` — drain inbox + unscoped-bd queues into structured tasks. *Hands off to `plan` (new) or `scope` (retrofit). Never starts execution.*
- `label` *(orthogonal)* — apply plain labels or namespaced external refs (`jira:`, `linear:`, `gh:`, `figma:`); namespaced refs propagate into the plan's frontmatter + Obsidian wikilinks.
- `manifest` *(orthogonal)* — register or update a project entry in `$AGENT_HOME/manifest.md` so `plan`/`scope` can validate labels against it.
- `persona` *(orthogonal)* — invoke a saved reviewer voice over a target (file, bd-id, diff, prose). Used internally by `summarize`; standalone-callable too.

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
- `dolt` on `$PATH` — beads' storage backend ([dolthub/dolt](https://github.com/dolthub/dolt))
- `jq` on `$PATH` (used by the auto-attach hook to parse `bd show --json`)
- `bash` and POSIX `awk` (everywhere)

The Quickstart script above handles `bd` and `dolt` for you.

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

### Optional: starter content

The Quickstart installer offers to seed these for you (step 5/5). To do it manually, drop-in scaffolds live under [`examples/`](./examples/) — copy what you need, edit to taste:

- [`examples/manifest.md`](./examples/manifest.md) → `$AGENT_HOME/manifest.md`. Sample project manifest used by `/bdx:plan` and `/bdx:scope` to validate project + component labels in monorepos. Plugin works without it; you'll just see "this repo isn't in the manifest" warnings on first plan.
- [`examples/personas/`](./examples/personas/) → `$AGENT_HOME/personas/`. Example reviewer voices (DHH, Linus Torvalds) used by `/bdx:summarize` to attach per-persona reviews. Fully optional — with no personas installed, the persona section is simply absent from summaries.

## Install the Claude Code plugin

**One-liner:**
```bash
claude plugin marketplace add zeejers/bdx-plugin && claude plugin install bdx@bdx-marketplace
```

The marketplace and plugin names (`bdx-marketplace`, `bdx`) are defined in [`.claude-plugin/marketplace.json`](./.claude-plugin/marketplace.json) — they're not the repo name. Changes activate on the next `claude` session; if you're already in one, run `/reload-plugins`.

**Local dev** (symlink approach, easiest to iterate on the plugin itself):
```bash
claude --plugin-dir ~/src/github.com/bdx-plugin
```

## Recommended: skip permission prompts for bdx

Every `/bdx:*` skill fires `bd` subcommands and writes to `$AGENT_HOME/`. Without an allowlist, Claude Code prompts on each one — which defeats most of the point of the skills.

Drop this into `~/.claude/settings.json` (or the project-level `.claude/settings.json`):

```json
{
  "permissions": {
    "allow": [
      "Bash(bd:*)",
      "Read(~/.bdx-agent/**)",
      "Write(~/.bdx-agent/**)",
      "Edit(~/.bdx-agent/**)"
    ]
  }
}
```

> Claude Code expands `~` to `$HOME` in `permissions.allow` paths, but **does not** expand shell env vars like `$AGENT_HOME` — those would be treated as literal strings. If you've overridden `AGENT_HOME` (e.g. `~/Dropbox/Notes/agent`), swap that path into the three `~/.bdx-agent/**` entries explicitly.

The Quickstart installer (step 6/6) handles this for you — it resolves `$AGENT_HOME` at install time, rewrites the `$HOME` prefix to `~`, and merges the resulting allowlist into your `~/.claude/settings.json`. The `Bash(bd:*)` line covers every bd subcommand; destructive `bd close` calls are still caught by the plugin's `PreToolUse` guard hook, so you don't lose the summary-first invariant.

## Usage

A normal task lifecycle, end to end:

**1. Plan.** Chat with the agent for a while about what you want to build, then run `/bdx:plan` to plan from the discussion — or `/bdx:plan "feature I want to work on"` to plan from a one-liner. You get back a beads issue (e.g. `bd-abc`) plus a structured plan file at `$AGENT_HOME/plan/bd-abc-<slug>.md`.

**2. Attach.** From any Claude session, run `/bdx:attach bd-abc`. The session loads the plan, every prior context dump, and the latest summary into turn-1 context — your agent picks up with full history of everything tagged with that bd-id in frontmatter.

> From a fresh terminal: `bdc bd-abc` launches `claude` with the task already attached (sets `BD_ID`, the SessionStart hook does the rest). No `/bdx:attach` needed.

**3. Dump.** Sign off fearlessly mid-session with `/bdx:dump`. A timestamped context snapshot lands in `$AGENT_HOME/context/` with the bd-id in its frontmatter. Next `/bdx:attach` pulls it in automatically alongside the plan and any other bd-id-tagged files.

**4. Close.** Finish the work, then `/bdx:close bd-abc` writes a summary to `$AGENT_HOME/summary/`, attributes decisions to agent vs user, and closes the bd issue with a one-line resolution. The plugin's `PreToolUse` hook blocks bare `bd close` so you can't accidentally skip the writeup.

Override for the rare raw close (e.g. closing an abandoned task without a summary):
```bash
BDX_ALLOW_BARE_BD_CLOSE=1 bd close bd-abc
```

## Escape hatches

- `BD_ID` unset → SessionStart hook is a silent no-op; normal `claude` invocations are unaffected
- `BDX_ALLOW_BARE_BD_CLOSE=1` → bypass the `bd close` guard for one command

## FAQ

### Why am I installing dolt for an issue tracker?

You're not, really — you're installing it for `bd`. [Beads](https://github.com/gastownhall/beads) is the issue tracker; it ships with [Dolt](https://github.com/dolthub/dolt) as its storage backend. Dolt is a SQL database with git-style branching, merging, and history. That's not overkill once you see what beads does with it: every issue mutation is a versioned change you can branch, diff, and three-way-merge — the same way you handle code.

For bdx specifically, that backend is what makes the rest of the workflow work. Tasks, comments, and status transitions persist across sessions, machines, and branches. Hook one shared dolt server up to a single `$BEADS_DIR`, sync `$AGENT_HOME` via Dropbox/iCloud, and your agents have a real persistence layer — not a chat log, not a markdown TODO, not a per-repo SQLite that fragments the moment you `cd` somewhere else. Beads is well-established and battle-tested; bdx just sits on top and couples each task to a durable markdown notebook.

If `dolt` weren't part of `bd`, the bdx workflow wouldn't be able to keep agent context coherent across sessions. So the installer takes both.

### Do I need a separate dolt server running?

`bd` auto-starts one transparently in the background the first time it needs it. You can run `bd dolt status` to see it. The default mode is "shared server" — one `dolt sql-server` process serves every project on the machine, listening on a local port. If you set `BEADS_DIR` globally (the bdx-recommended setup), there's exactly one beads database for everything you do.

### Can I skip dolt and use SQLite?

Beads has a `no-db` JSONL-only mode (set `no-db: true` in `~/.beads/config.yaml`), but you lose the branchable history that makes the agent persistence story work. The installer's `--skip-dolt` flag exists if you want to go down that path; bdx itself doesn't care about the storage layer, only that `bd` works.
