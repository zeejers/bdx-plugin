#!/bin/bash
# SessionStart hook: expose current session's UUID as $CLAUDE_SESSION_ID
# to downstream tool calls. Used by /bdx:plan, /bdx:dump, /bdx:summarize to
# record the session that produced each artifact in the plan's sessions:
# frontmatter list, so `claude --resume <uuid>` can pick the work back up.
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -n "$SESSION_ID" ] && [ -n "$CLAUDE_ENV_FILE" ] && \
  echo "export CLAUDE_SESSION_ID=$SESSION_ID" >> "$CLAUDE_ENV_FILE"
exit 0
