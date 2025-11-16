#!/bin/bash
# SubagentStop hook: Inject captured prompts into agent transcripts

set -e

# Setup logging (only if debug mode enabled)
if [[ "$CLAUDE_HOOK_DEBUG" == "1" ]]; then
    mkdir -p ~/.claude/logs
    LOG_FILE="$HOME/.claude/logs/subagent_hook.log"
fi

log() {
    if [[ "$CLAUDE_HOOK_DEBUG" == "1" ]]; then
        echo "[$(date)] $*" >> "$LOG_FILE"
    fi
}

# Read hook input
input=$(cat)

# Extract fields
agent_id=$(echo "$input" | jq -r '.agent_id // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')
agent_transcript=$(echo "$input" | jq -r '.agent_transcript_path // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

log "SubagentStop: agent_id=$agent_id"

# Validate inputs
if [[ -z "$agent_id" ]] || [[ -z "$agent_transcript" ]]; then
    log "Missing agent_id or agent_transcript_path"
    exit 0
fi

if [[ ! -f "$agent_transcript" ]]; then
    log "Agent transcript not found: $agent_transcript"
    exit 0
fi

# Check if first entry is already a user message (already injected)
first_type=$(head -1 "$agent_transcript" | jq -r '.type // empty' 2>/dev/null)
if [[ "$first_type" == "user" ]]; then
    log "First entry already user type, skipping injection (already processed)"
    # Still output agent ID for main agent to see
    echo "✓ Subagent completed (ID: $agent_id)"
    exit 0
fi

# Read prompts from queue (captured by PreToolUse hook)
queue_file="/tmp/task_prompts_queue.jsonl"
if [[ ! -f "$queue_file" ]]; then
    log "No prompts queue found"
    exit 0
fi

# Find prompts for this session (we don't have agent_id until now, so match by session and recent time)
# Get the most recent prompt for this session using jq (handles multiline JSON)
prompt_entry=$(jq -c "select(.session_id == \"$session_id\")" "$queue_file" | tail -1 || echo "")

if [[ -z "$prompt_entry" ]]; then
    log "No prompt found in queue for session $session_id"
    exit 0
fi

prompt=$(echo "$prompt_entry" | jq -r '.prompt')
timestamp=$(echo "$prompt_entry" | jq -r '.timestamp')

log "Injecting prompt: $(echo "$prompt" | head -c 50)..."

# Create user message entry in agent transcript format
user_entry=$(jq -n \
    --arg agent_id "$agent_id" \
    --arg session_id "$session_id" \
    --arg timestamp "$timestamp" \
    --arg prompt "$prompt" \
    --arg cwd "$cwd" \
    '{
        parentUuid: null,
        isSidechain: true,
        userType: "external",
        cwd: $cwd,
        sessionId: $session_id,
        version: "2.0.42",
        gitBranch: "subagents",
        agentId: $agent_id,
        type: "user",
        message: {
            role: "user",
            content: $prompt
        },
        timestamp: $timestamp
    }')

# Prepend to agent transcript (for initial dispatch, prompt should be FIRST)
# Create temp file with user entry first, then original content
echo "$user_entry" > "${agent_transcript}.tmp"
cat "$agent_transcript" >> "${agent_transcript}.tmp"
mv "${agent_transcript}.tmp" "$agent_transcript"

# Output agent ID to stdout (main agent will see this)
echo "✓ Subagent dispatched (ID: $agent_id)"

log "Injected prompt for agent $agent_id"

# Clean up old queue entries (keep last 100)
tail -100 "$queue_file" > "${queue_file}.tmp" && mv "${queue_file}.tmp" "$queue_file"

exit 0
