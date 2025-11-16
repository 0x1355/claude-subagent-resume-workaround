#!/bin/bash
# PreToolUse hook: Capture Task tool prompts before they're sent to subagents

set -e

# Setup logging (only if debug mode enabled)
if [[ "$CLAUDE_HOOK_DEBUG" == "1" ]]; then
    mkdir -p ~/.claude/logs
    LOG_FILE="$HOME/.claude/logs/task_prompts.log"
fi

log() {
    if [[ "$CLAUDE_HOOK_DEBUG" == "1" ]]; then
        echo "[$(date)] $*" >> "$LOG_FILE"
    fi
}

# Read hook input
input=$(cat)

# Extract prompt from tool_input
prompt=$(echo "$input" | jq -r '.tool_input.prompt // empty')
resume=$(echo "$input" | jq -r '.tool_input.resume // empty')
subagent_type=$(echo "$input" | jq -r '.tool_input.subagent_type // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')

log "Captured Task: subagent_type=$subagent_type, resume=$resume"

# Skip if no prompt
if [[ -z "$prompt" ]]; then
    exit 0
fi

# Handle RESUME vs DISPATCH differently
if [[ -n "$resume" ]] && [[ "$resume" != "null" ]] && [[ "$resume" != "" ]]; then
    # RESUME: Append prompt to existing agent transcript immediately
    cwd=$(echo "$input" | jq -r '.cwd // env.CLAUDE_PROJECT_DIR // empty')
    project_dir=$(dirname "$(find ~/.claude/projects -name "agent-$resume.jsonl" 2>/dev/null | head -1)")
    agent_transcript="$project_dir/agent-$resume.jsonl"

    log "RESUME: Appending to agent $resume at $agent_transcript"

    if [[ -f "$agent_transcript" ]]; then
        user_entry=$(jq -n \
            --arg agent_id "$resume" \
            --arg session_id "$session_id" \
            --arg timestamp "$(date -Iseconds)" \
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

        echo "$user_entry" >> "$agent_transcript"
        log "RESUME: Appended prompt to $agent_transcript"
    else
        log "RESUME: Transcript not found: $agent_transcript"
    fi
else
    # DISPATCH: Store prompt for SubagentStop to prepend later
    prompt_entry=$(jq -n \
        --arg session_id "$session_id" \
        --arg prompt "$prompt" \
        --arg resume "$resume" \
        --arg subagent_type "$subagent_type" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            session_id: $session_id,
            prompt: $prompt,
            resume: $resume,
            subagent_type: $subagent_type,
            timestamp: $timestamp
        }')

    echo "$prompt_entry" >> /tmp/task_prompts_queue.jsonl
    log "DISPATCH: Queued for SubagentStop"
fi

exit 0
