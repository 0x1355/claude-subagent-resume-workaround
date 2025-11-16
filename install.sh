#!/bin/bash
# Installation script for Claude Code Subagent Resume Workaround

set -e

# Parse command line arguments
LEVEL="user"
while [[ $# -gt 0 ]]; do
  case $1 in
    --level)
      LEVEL="$2"
      shift 2
      ;;
    --help|-h)
      echo "Claude Code Subagent Resume Workaround Installer"
      echo ""
      echo "Usage: $0 [--level local|shared|user]"
      echo ""
      echo "Options:"
      echo "  --level user     Install to ~/.claude/settings.json (default)"
      echo "  --level shared   Install to ~/.config/claude/settings.json"
      echo "  --level local    Install to ./.claude/settings.json"
      echo "  --help, -h       Show this help message"
      echo ""
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--level local|shared|user]"
      echo "Use --help for more information"
      exit 1
      ;;
  esac
done

# Validate level
if [[ ! "$LEVEL" =~ ^(local|shared|user)$ ]]; then
  echo "Error: --level must be one of: local, shared, user"
  echo "Usage: $0 [--level local|shared|user]"
  exit 1
fi

# Determine settings path based on level
case "$LEVEL" in
  user)
    SETTINGS_PATH="$HOME/.claude/settings.json"
    SETTINGS_DIR="$HOME/.claude"
    ;;
  shared)
    SETTINGS_PATH="$HOME/.config/claude/settings.json"
    SETTINGS_DIR="$HOME/.config/claude"
    ;;
  local)
    SETTINGS_PATH="./.claude/settings.json"
    SETTINGS_DIR="./.claude"
    ;;
esac

echo "Installing Claude Code Subagent Resume Workaround..."
echo "Settings level: $LEVEL"
echo "Settings path: $SETTINGS_PATH"
echo ""

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "⚠️  Warning: jq is not installed."
    echo "   For automatic merging of settings, please install jq:"
    echo "   - Ubuntu/Debian: sudo apt-get install jq"
    echo "   - macOS: brew install jq"
    echo "   - Fedora: sudo dnf install jq"
    echo ""
    echo "   Falling back to manual installation instructions..."
    JQ_AVAILABLE=false
else
    JQ_AVAILABLE=true
fi

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
echo ""

# Define the hooks configuration
HOOKS_CONFIG=$(cat << 'EOF'
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
    ],
    "PostToolUse": [
      {
        "matcher": "Task",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOME/.claude/scripts/task-posttooluse.sh"
          }
        ]
      }
    ]
  }
}
EOF
)

# Create settings directory if it doesn't exist
mkdir -p "$SETTINGS_DIR"

# Handle settings.json
if [[ ! -f "$SETTINGS_PATH" ]]; then
    # File doesn't exist, create it
    echo "Creating $SETTINGS_PATH..."
    echo "$HOOKS_CONFIG" > "$SETTINGS_PATH"
    echo "✓ Created settings.json with hooks configuration"
elif [[ "$JQ_AVAILABLE" = true ]]; then
    # File exists and jq is available, merge settings
    echo "Found existing $SETTINGS_PATH"

    # Create backup
    BACKUP_PATH="${SETTINGS_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS_PATH" "$BACKUP_PATH"
    echo "✓ Backup created: $BACKUP_PATH"

    # Merge hooks configuration
    echo "Merging hooks configuration..."
    TEMP_FILE=$(mktemp)

    # Use jq to deep merge the hooks
    jq -s 'def merge_hooks: . as [$a, $b] |
           ($a // {}) * ($b // {}) |
           .hooks.PreToolUse = ([$a.hooks.PreToolUse // [], $b.hooks.PreToolUse // []] | add | unique_by(.matcher)) |
           .hooks.SubagentStop = ([$a.hooks.SubagentStop // [], $b.hooks.SubagentStop // []] | add | unique_by(.matcher)) |
           .hooks.PostToolUse = ([$a.hooks.PostToolUse // [], $b.hooks.PostToolUse // []] | add | unique_by(.matcher));
           merge_hooks' \
           "$SETTINGS_PATH" <(echo "$HOOKS_CONFIG") > "$TEMP_FILE"

    # Validate the merged JSON
    if jq empty "$TEMP_FILE" 2>/dev/null; then
        mv "$TEMP_FILE" "$SETTINGS_PATH"
        echo "✓ Hooks merged into existing settings.json"
        echo "  (Previous version backed up to $BACKUP_PATH)"
    else
        echo "❌ Error: Failed to merge settings (invalid JSON produced)"
        echo "   Your original settings are safe at: $SETTINGS_PATH"
        echo "   Attempted merge saved to: $TEMP_FILE"
        rm -f "$TEMP_FILE"
        exit 1
    fi
else
    # File exists but jq is not available
    echo ""
    echo "⚠️  $SETTINGS_PATH already exists"
    echo "    (jq not available for automatic merging)"
    echo ""
    echo "Please manually add the following hooks to your settings.json:"
    echo ""
    echo "$HOOKS_CONFIG"
    echo ""
    echo "Make sure to merge carefully with your existing hooks configuration!"
    echo ""
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Restart Claude Code for hooks to take effect"
echo "2. Test with: 'Use general-purpose agent to remember code TEST-123'"
echo "3. Check logs: tail -f ~/.claude/logs/task_prompts.log"
echo ""
