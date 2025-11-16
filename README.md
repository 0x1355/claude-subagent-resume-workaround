# Claude Code Subagent Resume Fix

**Temporary workaround** for the missing user prompts in subagent transcripts bug in Claude Code 2.0.42.

This workaround will be deprecated once the official fix is released.

## The Problem

Claude Code subagent transcripts don't store user prompts - only assistant responses and tool results. This causes:
- Resume to fail after 2-3 iterations (context drift/hallucination)
- Agents forgetting what you asked them to do
- Loss of precise data (codes, paths, values get corrupted)

See [bug report](https://github.com/anthropics/claude-code/issues/11712) for full details.

## The Solution

This workaround uses three hooks to fix subagent resume and make agent IDs visible:

- **PreToolUse (Task)** - Captures prompts before Task tool executes
- **SubagentStop** - Injects prompts into agent transcripts in correct chronological order
- **PostToolUse (Task)** - Injects agent IDs into parent context for visibility

**Result:** Subagent resume works reliably across multiple turns, and main agent automatically sees all agent IDs

## Requirements

- **jq** - JSON processor (required for all hook scripts)

**Install jq:**

```bash
# Ubuntu/Debian
sudo apt-get install jq

# Alpine (Docker containers)
apk add jq

# macOS
brew install jq

# Fedora/RHEL
sudo dnf install jq
```

## Installation

**Single command installation:**

```bash
./install.sh
```

**Options:**

```bash
./install.sh --level <local|shared|user>
```

- `--level user` (default): Install to `~/.claude/settings.json`
- `--level shared`: Install to `~/.config/claude/settings.json`
- `--level local`: Install to `./.claude/settings.json` (current directory)

**What it does:**

- Copies hook scripts to `~/.claude/scripts/`
- Creates automatic backup of existing settings (with timestamp)
- Intelligently merges hooks into your settings.json (requires `jq`)
- Makes all scripts executable
- Preserves all your existing settings

**Note:** If `jq` is not installed, the installer will still copy the hook scripts but will show manual merge instructions instead of automatically merging settings. However, **the hooks themselves require jq to function**.

**Then restart Claude Code** for hooks to take effect

## Testing

Test with a simple dispatch and resume:

```bash
# Dispatch
> Use general-purpose agent to remember code APPLE-123 and standby

# The main agent will automatically see in its context:
# "✓ Subagent dispatched (ID: abc123def)"

# Resume with that agent ID
> Resume agent abc123def and tell me the code
```

The agent should correctly remember APPLE-123.

**Agent ID Visibility:** After each Task tool completes, the main agent automatically receives the agent ID in its context via PostToolUse hook. No manual tracking needed!

## How It Works

### For New Dispatches (DISPATCH):
1. **PreToolUse** captures prompt → stores in queue (`/tmp/task_prompts_queue.jsonl`)
2. Agent executes → writes assistant responses to transcript
3. **SubagentStop** fires → reads queue → **prepends** user prompt to top of transcript
4. **PostToolUse** fires → extracts agent ID → injects into parent context via `additionalContext`
5. Result: `user → assistant` (correct order) + main agent sees agent ID

### For Resumes (RESUME):
1. **PreToolUse** detects resume parameter → **appends** user prompt immediately to existing transcript
2. Agent executes → writes assistant response
3. **SubagentStop** fires → sees first entry is already user → skips (prevents duplicates)
4. **PostToolUse** fires → injects agent ID into parent context
5. Result: `...existing → user → assistant` (correct order) + main agent sees agent ID

## Verification

After each Task tool completes, the main agent's context will include:
```
PostToolUse:Task hook additional context: ✓ Subagent dispatched (ID: abc123def)
```

This appears as a system reminder visible to the main agent, allowing it to reference the agent ID for resume operations.

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
- Verify `jq` is installed: `which jq`
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
