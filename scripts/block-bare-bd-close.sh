#!/bin/bash
# PreToolUse hook: block `bd close` in Bash tool calls so Claude is forced
# to go through /bdx:bd.close (which runs bdx:bd.summarize first, then closes the
# bd issue with a resolution). Summaries otherwise get skipped and history
# is lost.
#
# Bypass: set QF_ALLOW_BARE_BD_CLOSE=1 in the session env (rare — normally
# you never want this; /bdx:bd.close handles the abandoned case too).

set -u

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

# Skip help invocations
if printf '%s' "$CMD" | grep -Eq '\bbd[[:space:]]+close\b[[:space:]]+(-h\b|--help\b)'; then
  exit 0
fi

# Bypass escape hatch
[ "${QF_ALLOW_BARE_BD_CLOSE:-}" = "1" ] && exit 0

# Match `bd close` or `bd update ... --status closed` anywhere in the command
# (chaining with && ; || | all handled via the leading-boundary class)
BOUNDARY='(^|[[:space:];&|])'
if printf '%s' "$CMD" | grep -Eq "${BOUNDARY}bd[[:space:]]+close\b" \
  || printf '%s' "$CMD" | grep -Eq "${BOUNDARY}bd[[:space:]]+update\b.*--status[[:space:]=]+closed\b"; then
  cat >&2 <<'EOF'
Blocked: do not call `bd close` directly.

Run `/bdx:bd.close <bd-id>` instead — it writes a summary via bdx:bd.summarize
(recording what was built + decisions + links), then closes the bd issue
with a resolution message. Without the summary, task history is lost.

For abandoned work: `/bdx:bd.close <bd-id> abandoned because <reason>` still
closes, it just records the abandonment rationale.

Escape hatch (rare): `QF_ALLOW_BARE_BD_CLOSE=1 bd close ...`
EOF
  exit 2
fi

exit 0
