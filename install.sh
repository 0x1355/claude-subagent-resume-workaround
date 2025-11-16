#!/bin/bash
# Installation script for Claude Code Subagent Resume Workaround

set -e

echo "Installing Claude Code Subagent Resume Workaround..."

# Create scripts directory
mkdir -p ~/.claude/scripts

# Copy scripts
cp capture-task-prompt.sh ~/.claude/scripts/
cp inject-agent-prompts.sh ~/.claude/scripts/
cp task-posttooluse.sh ~/.claude/scripts/

# Make executable
chmod +x ~/.claude/scripts/capture-task-prompt.sh
chmod +x ~/.claude/scripts/inject-agent-prompts.sh
chmod +x ~/.claude/scripts/task-posttooluse.sh

echo "✓ Scripts installed to ~/.claude/scripts/"

# Check if settings.json exists
if [[ ! -f ~/.claude/settings.json ]]; then
    echo "Creating ~/.claude/settings.json..."
    cat > ~/.claude/settings.json << 'EOF'
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
EOF
    echo "✓ Created settings.json with hooks configuration"
else
    echo ""
    echo "⚠️  ~/.claude/settings.json already exists"
    echo "Please manually add the following to your settings.json:"
    echo ""
    cat << 'EOF'
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
EOF
    echo ""
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Restart Claude Code for hooks to take effect"
echo "2. Test with: 'Use general-purpose agent to remember code TEST-123'"
echo "3. Check logs: tail -f /tmp/subagent_hook_debug.log"
echo ""
