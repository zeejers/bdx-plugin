#!/bin/bash
# PreToolUse hook: block `bd close` in Bash tool calls so Claude is forced
# to go through /bdx:close (which runs /bdx:summarize first, then closes the
# bd issue with a resolution). Summaries otherwise get skipped and history
# is lost.
#
# Bypass: include `BDX_ALLOW_BARE_BD_CLOSE=1` as an inline env assignment
# in the bash command itself — e.g. `BDX_ALLOW_BARE_BD_CLOSE=1 bd close bd-xxx`.
# The hook inspects the command string (not its own env) so this works when
# /bdx:close drives the close, and for rare manual overrides.

set -u

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

# Skip help invocations
if printf '%s' "$CMD" | grep -Eq '\bbd[[:space:]]+close\b[[:space:]]+(-h\b|--help\b)'; then
  exit 0
fi

# Bypass escape hatch — look for the inline env assignment in the command
# string itself (the hook's own env won't see inline prefixes, since the
# hook runs before the Bash subshell interprets the assignment).
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:];&|])BDX_ALLOW_BARE_BD_CLOSE=1\b'; then
  exit 0
fi

# Match `bd close` or `bd update ... --status closed` anywhere in the command
# (chaining with && ; || | all handled via the leading-boundary class)
BOUNDARY='(^|[[:space:];&|])'
if printf '%s' "$CMD" | grep -Eq "${BOUNDARY}bd[[:space:]]+close\b" \
  || printf '%s' "$CMD" | grep -Eq "${BOUNDARY}bd[[:space:]]+update\b.*--status[[:space:]=]+closed\b"; then
  cat >&2 <<'EOF'
Blocked: do not call `bd close` directly.

Run `/bdx:close <bd-id>` instead — it writes a summary via /bdx:summarize
(recording what was built + decisions + links), then closes the bd issue
with a resolution message. Without the summary, task history is lost.

For abandoned work: `/bdx:close <bd-id> abandoned because <reason>` still
closes, it just records the abandonment rationale.

Escape hatch (rare): prefix the close command with the bypass env var,
e.g.  `BDX_ALLOW_BARE_BD_CLOSE=1 bd close bd-xxx`
EOF
  exit 2
fi

exit 0
