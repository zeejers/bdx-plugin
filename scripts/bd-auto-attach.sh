#!/bin/bash
# SessionStart hook: if $BD_ID is set in the parent env, auto-attach this
# session to that beads task without running the /bdx:bd.attach skill manually.
#
# Actions:
#   1. Verify the bd issue exists
#   2. If status is `open`, flip to `in_progress`
#   3. Append this session's UUID to the plan file's `sessions:` frontmatter
#      (idempotent — no-op if already present)
#   4. Emit a briefing (plan + latest context + latest summary + recent
#      comments) as `additionalContext` so Claude starts pre-loaded
#
# Opt in by launching as:
#   BD_ID=bd-xxx claude -n "bd-xxx-<slug>"
# or use the `bdc` shell function (see ~/.claude/hooks/bdc).

set -u

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty')

# Only act on fresh startup — resume/clear/compact already have context
[ "$SOURCE" = "startup" ] || exit 0

BD_ID="${BD_ID:-}"
[ -n "$BD_ID" ] || exit 0  # not a bd-attached session, no-op

AGENT_HOME="${AGENT_HOME:-$HOME/Dropbox/Notes/agent}"

# Verify bd issue + capture JSON (bd exits non-zero + emits {"error": ...} if missing)
if ! ISSUE_JSON=$(bd show "$BD_ID" --json 2>/dev/null); then
  echo "bd-auto-attach: $BD_ID not found; skipping" >&2
  exit 1
fi
if [ "$(printf '%s' "$ISSUE_JSON" | jq -r 'type')" != "array" ] || \
   [ "$(printf '%s' "$ISSUE_JSON" | jq 'length')" = "0" ]; then
  echo "bd-auto-attach: unexpected bd output for $BD_ID; skipping" >&2
  exit 1
fi

STATUS=$(printf '%s' "$ISSUE_JSON" | jq -r '.[0].status // empty')
TITLE=$(printf '%s' "$ISSUE_JSON" | jq -r '.[0].title // empty')

# Flip open → in_progress
if [ "$STATUS" = "open" ]; then
  bd update "$BD_ID" --status in_progress >/dev/null 2>&1 || true
fi

# Locate plan (1 per task by convention)
PLAN=$(ls "$AGENT_HOME"/plan/"$BD_ID"-*.md 2>/dev/null | head -1)

# Append session UUID to plan frontmatter (idempotent)
if [ -n "$PLAN" ] && [ -n "$SESSION_ID" ]; then
  python3 - "$PLAN" "$SESSION_ID" <<'PY' || true
import sys, re, pathlib
path, sid = sys.argv[1], sys.argv[2]
p = pathlib.Path(path)
text = p.read_text()
m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
if not m:
    sys.exit(0)
fm = m.group(1)
lines = fm.split('\n')
out, i, found, changed = [], 0, False, False
while i < len(lines):
    line = lines[i]
    out.append(line)
    if re.match(r'^sessions\s*:\s*$', line) or re.match(r'^sessions\s*:\s*\[\s*\]\s*$', line):
        found = True
        j = i + 1
        entries = []
        while j < len(lines) and re.match(r'^\s+-\s', lines[j]):
            entries.append(lines[j])
            j += 1
        if not any(sid in e for e in entries):
            entries.append(f"  - {sid}")
            changed = True
        out.extend(entries)
        i = j
        continue
    i += 1
if not found:
    out.append("sessions:")
    out.append(f"  - {sid}")
    changed = True
if changed:
    new = "---\n" + "\n".join(out) + "\n---\n" + text[m.end():]
    p.write_text(new)
PY
fi

# Pick latest context + summary for this bd-id
latest_with_bd() {
  local dir="$1"
  [ -d "$dir" ] || return
  grep -l "^bd: *$BD_ID\$" "$dir"/*.md 2>/dev/null | while read -r f; do
    printf '%s\t%s\n' "$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f")" "$f"
  done | sort -rn | head -1 | cut -f2-
}
LATEST_CTX=$(latest_with_bd "$AGENT_HOME/context")
LATEST_SUM=$(latest_with_bd "$AGENT_HOME/summary")

# Build briefing
CTX=$(mktemp)
{
  echo "# Auto-attached to $BD_ID — ${TITLE:-(no title)}"
  echo
  echo "Status flipped to **in_progress** (was $STATUS)."
  echo "Session UUID appended to plan \`sessions:\` list."
  echo
  if [ -n "$PLAN" ]; then
    echo "## Plan — $PLAN"
    echo
    echo '```markdown'
    head -400 "$PLAN"
    echo '```'
    echo
  else
    echo "_No plan file found at $AGENT_HOME/plan/$BD_ID-*.md._"
    echo
  fi
  if [ -n "$LATEST_CTX" ]; then
    echo "## Latest context dump — $LATEST_CTX"
    echo
    echo '```markdown'
    head -200 "$LATEST_CTX"
    echo '```'
    echo
  fi
  if [ -n "$LATEST_SUM" ]; then
    echo "## Latest summary — $LATEST_SUM"
    echo
    echo '```markdown'
    head -120 "$LATEST_SUM"
    echo '```'
    echo
  fi
  COMMENTS=$(bd comments "$BD_ID" 2>/dev/null | tail -80)
  if [ -n "$COMMENTS" ] && [ "$COMMENTS" != "No comments on $BD_ID" ]; then
    echo "## Recent bd comments"
    echo
    echo '```'
    echo "$COMMENTS"
    echo '```'
  fi
} > "$CTX"

jq -Rs --arg title "bd-attached: $BD_ID" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    sessionTitle: $title,
    additionalContext: .
  }
}' < "$CTX"

rm -f "$CTX"
exit 0
