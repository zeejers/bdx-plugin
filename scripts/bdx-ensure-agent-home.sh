#!/bin/bash
# SessionStart hook: ensure $AGENT_HOME is set + the expected subdirs exist.
# Runs every session (independent of $BD_ID) so downstream skills and hooks
# that reference $AGENT_HOME can rely on it. Default is ~/.bdx-agent; override
# by exporting AGENT_HOME in your shell rc before launching claude.
#
# Exports the resolved value via $CLAUDE_ENV_FILE so all subsequent Bash tool
# calls in the session see it.

set -u

AGENT_HOME_DEFAULT="$HOME/.bdx-agent"
AGENT_HOME="${AGENT_HOME:-$AGENT_HOME_DEFAULT}"

# Ensure the canonical subdirs exist (idempotent)
mkdir -p "$AGENT_HOME/plan" "$AGENT_HOME/context" "$AGENT_HOME/summary" "$AGENT_HOME/inbox"

# Propagate to downstream tool calls in this session
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export AGENT_HOME=$AGENT_HOME" >> "$CLAUDE_ENV_FILE"
fi

exit 0
