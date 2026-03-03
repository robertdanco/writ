#!/usr/bin/env bash
# init.sh - Install Writ into a target project directory
# Usage: ./init.sh [target-directory]
# Safe to re-run (idempotent).

set -euo pipefail

# --- Config ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$(pwd)}"
WRIT_HEADER="# Writ Protocol"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[writ]${NC} $1"; }
ok()    { echo -e "${GREEN}[ok]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $1"; }

# --- Validate ---
if [ ! -d "$TARGET_DIR" ]; then
  echo "ERROR: Target directory does not exist: $TARGET_DIR"
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/templates/writ-protocol.md" ]; then
  echo "ERROR: Writ harness files not found at $SCRIPT_DIR"
  echo "Run this script from the writ harness directory, or provide the correct path."
  exit 1
fi

info "Installing Writ into: $TARGET_DIR"

# --- Create directory structure ---
mkdir -p "$TARGET_DIR/.claude/commands"
mkdir -p "$TARGET_DIR/.claude/agents"
ok "Created .claude/commands/ and .claude/agents/"

# --- Copy command files ---
for cmd_file in "$SCRIPT_DIR/.claude/commands/"*.md; do
  filename="$(basename "$cmd_file")"
  dest="$TARGET_DIR/.claude/commands/$filename"
  cp "$cmd_file" "$dest"
  ok "Installed command: .claude/commands/$filename"
done

# --- Copy agent files ---
for agent_file in "$SCRIPT_DIR/.claude/agents/"*.md; do
  filename="$(basename "$agent_file")"
  dest="$TARGET_DIR/.claude/agents/$filename"
  cp "$agent_file" "$dest"
  ok "Installed agent: .claude/agents/$filename"
done

# --- Copy writ.json template (skip if exists) ---
if [ -f "$TARGET_DIR/writ.json" ]; then
  warn "writ.json already exists - skipping (use /writ-ingest to update it)"
else
  cp "$SCRIPT_DIR/templates/writ.json" "$TARGET_DIR/writ.json"
  ok "Created writ.json template"
fi

# --- Copy progress.json template (skip if exists) ---
if [ -f "$TARGET_DIR/progress.json" ]; then
  warn "progress.json already exists - skipping"
else
  cp "$SCRIPT_DIR/templates/progress.json" "$TARGET_DIR/progress.json"
  ok "Created progress.json template"
fi

# --- Copy progress.md template (skip if exists) ---
if [ -f "$TARGET_DIR/progress.md" ]; then
  warn "progress.md already exists - skipping"
else
  cp "$SCRIPT_DIR/templates/progress.md" "$TARGET_DIR/progress.md"
  ok "Created progress.md template"
fi

# --- Copy scripts ---
if [ -d "$SCRIPT_DIR/scripts" ]; then
  mkdir -p "$TARGET_DIR/scripts"
  for script_file in "$SCRIPT_DIR/scripts/"*.sh; do
    filename="$(basename "$script_file")"
    cp "$script_file" "$TARGET_DIR/scripts/$filename"
    chmod +x "$TARGET_DIR/scripts/$filename"
    ok "Installed scripts/$filename"
  done
fi

# --- Append Writ protocol to CLAUDE.md (idempotent) ---
CLAUDE_MD="$TARGET_DIR/CLAUDE.md"

if [ -f "$CLAUDE_MD" ] && grep -q "^$WRIT_HEADER" "$CLAUDE_MD" 2>/dev/null; then
  warn "CLAUDE.md already contains Writ Protocol section - skipping"
else
  # Add a blank line separator if CLAUDE.md already has content
  if [ -f "$CLAUDE_MD" ] && [ -s "$CLAUDE_MD" ]; then
    echo "" >> "$CLAUDE_MD"
    echo "---" >> "$CLAUDE_MD"
    echo "" >> "$CLAUDE_MD"
  fi
  cat "$SCRIPT_DIR/templates/writ-protocol.md" >> "$CLAUDE_MD"
  ok "Appended Writ Protocol to CLAUDE.md"
fi

# --- Initialize git if needed ---
if [ ! -d "$TARGET_DIR/.git" ]; then
  git -C "$TARGET_DIR" init -q
  ok "Initialized git repository"
else
  ok "Git repository already exists"
fi

# --- Print next steps ---
echo ""
echo "======================================"
echo "  Writ installed successfully"
echo "======================================"
echo ""
echo "Next steps:"
echo ""
echo "  1. Fill in build/test/start commands in CLAUDE.md"
echo "     (look for the '## Build and test commands' section)"
echo ""
echo "  2. Open Claude Code in your project:"
echo "     cd $TARGET_DIR && claude"
echo ""
echo "  3a. If you have a PRD or requirements document, run:"
echo "      /writ-ingest path/to/your/prd.md"
echo ""
echo "  3b. If starting from scratch, use the initializer agent:"
echo "      \"Use the writ-initializer agent to set up the project\""
echo ""
echo "  4. Begin development:"
echo "      /writ-status           - check project progress at any time"
echo "      /writ-plan             - preview implementation plan without coding"
echo "      /writ-session          - run a full implement-verify-commit session"
echo "      /writ-session <id>     - run a session for a specific feature"
echo ""
echo "  5. For autonomous mode (after verifying your spec is solid):"
echo "      bash scripts/writ-loop.sh               - dry run preview"
echo "      bash scripts/writ-loop.sh --confirm     - run autonomously"
echo ""
echo "  6. For CI integration:"
echo "      bash scripts/writ-export-checks.sh > ci-checks.sh"
echo "      cp $SCRIPT_DIR/templates/github-actions-writ.yml .github/workflows/writ-checks.yml"
echo ""
