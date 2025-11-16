#!/bin/bash
# PostToolUse hook for Task tool: Inject agent ID into parent context

set -e

# Check for jq dependency
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Hook requires jq for JSON parsing." >&2
    echo "Install: apt-get install jq (Ubuntu) | apk add jq (Alpine) | brew install jq (macOS)" >&2
    exit 1
fi

# Read hook input
input=$(cat)

# Extract agent ID from tool result
agent_id=$(echo "$input" | jq -r '.tool_response.agentId // empty')

# If no agent ID, exit silently
if [[ -z "$agent_id" ]]; then
    exit 0
fi

# Output JSON to inject agent ID into parent context
jq -n \
    --arg agent_id "$agent_id" \
    '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: ("✓ Subagent dispatched (ID: " + $agent_id + ")")
        }
    }'

exit 0
