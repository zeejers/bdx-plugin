# bdx

Claude Code plugin wrapping the [`bd` (beads)](https://github.com/gastownhall/beads) issue tracker into a full session-aware task workflow: auto-attach sessions to a bd task, enforce summary-before-close, and ship the full `bd.*` lifecycle as skills.

## What's in the box

### Skills (`/bdx:<name>`)
- `bd.plan` — create a bd issue + structured plan file
- `bd.attach` — resume an existing bd task, load plan/context/summary into the session
- `bd.dump` — mid-flight context snapshot (reloadable later)
- `bd.summarize` — post-implementation writeup to `$AGENT_HOME/summary/`
- `bd.close` — finalize a task (writes summary if missing, then closes with resolution)
- `bd.label` — apply plain labels or namespaced external refs (`jira:ABC-123`, `linear:FOO-456`)
- `bd.scope` — add project + component labels to an existing unscoped bd + write its plan
- `bd.triage` — drain inbox / unscoped bd issues into real tasks
- `bd.manifest` — inspect a project on disk and add/update its `$AGENT_HOME/manifest.md` entry

### Hooks
- **`SessionStart:startup`** → `bd-auto-attach.sh`
  If `$BD_ID` is set in the parent env, auto-loads the plan/context/summary, appends the session UUID to the plan's `sessions:` frontmatter, flips bd status `open → in_progress`, and emits the bundle as `additionalContext` on turn 1.
- **`PreToolUse:Bash`** → `block-bare-bd-close.sh`
  Blocks direct `bd close` (and `bd update --status closed`) so you're forced through `/bdx:bd.close`, which writes a summary first.

### Launcher
- `scripts/bdc` — `bdc <bd-id>` sets `BD_ID`, derives a slug from the bd title, and runs `claude -n "<bd-id>-<slug>"`. Symlink to `~/bin/bdc` or alias it.

## Prerequisites

- `bd` (beads) CLI on `$PATH`
- `$AGENT_HOME` set (defaults to `~/Dropbox/Notes/agent/`) with `plan/`, `context/`, `summary/`, `inbox/` subdirs
- `jq`, `python3` on `$PATH` (used by the auto-attach hook)

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
/bdx:bd.close bd-abc
```

Override for the rare raw close:
```bash
QF_ALLOW_BARE_BD_CLOSE=1 bd close bd-abc
```

## Escape hatches

- `BD_ID` unset → SessionStart hook is a silent no-op; normal `claude` invocations are unaffected
- `QF_ALLOW_BARE_BD_CLOSE=1` → bypass the `bd close` guard for one command
