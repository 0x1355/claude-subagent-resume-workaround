# Claude Code Subagent Resume Fix

**Temporary workaround** for the missing user prompts in subagent transcripts bug in Claude Code 2.0.42.

This workaround will be deprecated once the official fix is released.

## The Problem

Claude Code subagent transcripts don't store user prompts - only assistant responses and tool results. This causes:
- Resume to fail after 2-3 iterations (context drift/hallucination)
- Agents forgetting what you asked them to do
- Loss of precise data (codes, paths, values get corrupted)

See [bug report](link-to-issue) for full details.

## The Solution

This workaround uses hooks to capture user prompts and inject them into subagent transcripts in the correct chronological order:

- **PreToolUse hook** captures prompts before Task tool executes
- **SubagentStop hook** injects prompts into agent transcripts
- Result: Subagent resume works reliably across multiple turns

## Installation

1. **Copy hook scripts:**
   ```bash
   mkdir -p ~/.claude/scripts
   cp capture-task-prompt.sh ~/.claude/scripts/
   cp inject-agent-prompts.sh ~/.claude/scripts/
   chmod +x ~/.claude/scripts/*.sh
   ```

2. **Update Claude Code settings:**
   Add to `~/.claude/settings.json`:
   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Task",
           "hooks": [
             {
               "type": "command",
               "command": "bash $HOME/.claude/scripts/capture-task-prompt.sh"
             }
           ]
         }
       ],
       "SubagentStop": [
         {
           "matcher": "*",
           "hooks": [
             {
               "type": "command",
               "command": "bash $HOME/.claude/scripts/inject-agent-prompts.sh"
             }
           ]
         }
       ]
     }
   }
   ```

3. **Restart Claude Code** for hooks to take effect

## Testing

Test with a simple dispatch and resume:

```bash
# Dispatch
> Use general-purpose agent to remember code APPLE-123 and standby

# After it completes, find agent ID in logs:
tail -5 /tmp/subagent_hook_debug.log

# Resume with that agent ID
> Resume agent <agent-id> and tell me the code
```

The agent should correctly remember APPLE-123.

**Note:** After each subagent completes, you'll see a message like `✓ Subagent completed (ID: abc123)` - this is the agent ID you can use for resuming.

## How It Works

### For New Dispatches (DISPATCH):
1. PreToolUse captures prompt → stores in queue (`/tmp/task_prompts_queue.jsonl`)
2. Agent executes → writes assistant responses to transcript
3. SubagentStop fires → reads queue → **prepends** user prompt to top of transcript
4. Result: `user → assistant` (correct order)

### For Resumes (RESUME):
1. PreToolUse detects resume parameter → **appends** user prompt immediately to existing transcript
2. Agent executes → writes assistant response
3. SubagentStop fires → sees first entry is already user → skips (prevents duplicates)
4. Result: `...existing → user → assistant` (correct order)

## Verification

After each subagent completes, you should see:
```
✓ Subagent completed (ID: abc123def)
```

### Debug Mode (Optional)

Enable debug logging to troubleshoot issues:

```bash
# Set in your shell or .bashrc/.zshrc
export CLAUDE_HOOK_DEBUG=1

# Then check logs
tail -f ~/.claude/logs/task_prompts.log
tail -f ~/.claude/logs/subagent_hook.log

# Check a specific agent transcript
cat ~/.claude/projects/-<project-name>/agent-<agent-id>.jsonl | jq -c '{type: .type, role: .message.role}'

# Should show: user, assistant, user, assistant (alternating)
```

## Limitations

1. **Timing-dependent:** Uses queue file in `/tmp` - not suitable for distributed systems
2. **Log rotation:** Logs in `~/.claude/logs/` accumulate (no automatic rotation)
3. **Queue cleanup:** Queue keeps last 100 entries only
4. **Requires restart:** Hook changes need Claude Code restart to take effect
5. **Docker compatibility:** Uses `$HOME` which should work in most environments

## Compatibility

- **Tested on:** Claude Code 2.0.42, Linux
- **Should work on:** macOS, Docker containers (uses `$HOME`)
- **May need adjustment for:** Windows (path separators)

## Troubleshooting

**Hooks not running:**
- Check `~/.claude/settings.json` syntax is valid JSON
- Restart Claude Code
- Check script permissions: `ls -la ~/.claude/scripts/`
- Enable debug mode: `export CLAUDE_HOOK_DEBUG=1` and restart Claude Code

**Prompts not appearing in transcripts:**
- Enable debug logging: `export CLAUDE_HOOK_DEBUG=1`
- Check logs: `tail -20 ~/.claude/logs/subagent_hook.log`
- Verify queue file exists: `ls -la /tmp/task_prompts_queue.jsonl`
- Check first dispatch worked: `cat ~/.claude/logs/task_prompts.log`

**Resume still doesn't work:**
- Verify transcript has user entries: `cat <transcript> | jq '.type'`
- Check order is correct (user before assistant)
- Look for duplicates (SubagentStop should skip if first is user)

## When to Remove

Remove this workaround once Anthropic fixes the bug officially. Check for:
- Agent transcripts naturally containing user prompts
- Release notes mentioning subagent transcript fixes

## Credits

Solution developed through investigating Claude Code 2.0.42 behavior and hook system.

## License

MIT - Use freely, modify as needed
