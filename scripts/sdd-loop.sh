#!/usr/bin/env bash
# sdd-loop.sh - Run SDD sessions autonomously until all features complete
# Usage: ./sdd-loop.sh [--confirm] [--max-sessions N] [project-dir]
#
# By default runs in dry-run mode. Pass --confirm to actually execute.
# Pattern from Anthropic's C compiler case study (16 parallel agents, $20K, 100K LOC in 2 weeks).

set -euo pipefail

# --- Defaults ---
CONFIRM=false
MAX_SESSIONS=""
PROJECT_DIR="$(pwd)"
LOG_FILE="sdd-loop.log"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)    CONFIRM=true; shift ;;
    --max-sessions) MAX_SESSIONS="$2"; shift 2 ;;
    -*)           echo "Unknown flag: $1"; exit 1 ;;
    *)            PROJECT_DIR="$1"; shift ;;
  esac
done

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${BLUE}[loop]${NC} $1"; }
ok()      { echo -e "${GREEN}[done]${NC} $1"; }
warn()    { echo -e "${YELLOW}[warn]${NC} $1"; }
err()     { echo -e "${RED}[fail]${NC} $1"; }

log() {
  local msg="[$(date '+%Y-%m-%dT%H:%M:%S')] $1"
  echo "$msg" >> "$PROJECT_DIR/$LOG_FILE"
  echo "$msg"
}

# --- Validate ---
if [ ! -f "$PROJECT_DIR/spec.json" ]; then
  err "No spec.json found in $PROJECT_DIR"
  err "Run /sdd-ingest first to generate a spec, then use sdd-loop."
  exit 1
fi

# Count pending features using python (avoids jq dependency)
count_pending() {
  python3 -c "
import json, sys
with open('$PROJECT_DIR/spec.json') as f:
    spec = json.load(f)
pending = [f for f in spec.get('features', []) if f.get('status') in ('pending', 'in_progress')]
print(len(pending))
" 2>/dev/null || echo "0"
}

count_completed() {
  python3 -c "
import json, sys
with open('$PROJECT_DIR/spec.json') as f:
    spec = json.load(f)
done = [f for f in spec.get('features', []) if f.get('status') == 'completed']
print(len(done))
" 2>/dev/null || echo "0"
}

get_project_name() {
  python3 -c "
import json
with open('$PROJECT_DIR/spec.json') as f:
    spec = json.load(f)
print(spec.get('project', 'unknown'))
" 2>/dev/null || echo "unknown"
}

PENDING=$(count_pending)
COMPLETED=$(count_completed)
PROJECT=$(get_project_name)
MAX_SESSIONS="${MAX_SESSIONS:-$PENDING}"

if [ "$PENDING" -eq 0 ]; then
  ok "All features already complete for project: $PROJECT"
  exit 0
fi

# --- Dry-run preview ---
echo ""
echo "SDD Autonomous Loop"
echo "==================="
echo "Project:      $PROJECT"
echo "Directory:    $PROJECT_DIR"
echo "Pending:      $PENDING features"
echo "Completed:    $COMPLETED features"
echo "Max sessions: $MAX_SESSIONS"
echo "Log file:     $PROJECT_DIR/$LOG_FILE"
echo ""

if [ "$CONFIRM" = false ]; then
  warn "DRY RUN - no sessions will execute"
  warn "Add --confirm to run for real:"
  warn "  $0 --confirm $PROJECT_DIR"
  echo ""
  info "Would run up to $MAX_SESSIONS sessions targeting $PENDING pending features"
  exit 0
fi

# --- Safety checks ---
if [ ! -d "$PROJECT_DIR/.git" ]; then
  err "No git repository found. SDD requires git for state management."
  exit 1
fi

GIT_STATUS=$(git -C "$PROJECT_DIR" status --porcelain -uno 2>/dev/null || echo "ERROR")
if [ "$GIT_STATUS" = "ERROR" ]; then
  err "git status failed in $PROJECT_DIR"
  exit 1
fi
if [ -n "$GIT_STATUS" ]; then
  warn "Uncommitted changes detected:"
  git -C "$PROJECT_DIR" status --short
  echo ""
  read -r -p "Continue anyway? (y/N) " REPLY
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    info "Aborted. Commit or stash changes before running sdd-loop."
    exit 1
  fi
fi

# --- Main loop ---
SESSION=0
PROGRESS_MADE=true

log "=== SDD loop started: project=$PROJECT, pending=$PENDING, max=$MAX_SESSIONS ==="

while [ "$SESSION" -lt "$MAX_SESSIONS" ] && [ "$PROGRESS_MADE" = true ]; do
  SESSION=$((SESSION + 1))
  BEFORE=$(count_pending)

  log "--- Session $SESSION/$MAX_SESSIONS starting (pending: $BEFORE) ---"
  info "Session $SESSION/$MAX_SESSIONS..."

  # Run session in project directory
  # --dangerously-skip-permissions avoids interactive prompts in non-interactive mode
  if ! (cd "$PROJECT_DIR" && claude -p "/sdd-session" 2>>"$PROJECT_DIR/$LOG_FILE"); then
    log "Session $SESSION: claude exited non-zero"
    err "Session $SESSION failed. Check $LOG_FILE for details."
    break
  fi

  AFTER=$(count_pending)
  COMPLETED_NOW=$(count_completed)

  log "Session $SESSION complete: pending $BEFORE -> $AFTER, completed=$COMPLETED_NOW"

  if [ "$AFTER" -ge "$BEFORE" ]; then
    PROGRESS_MADE=false
    warn "No progress in session $SESSION (pending unchanged at $AFTER)"
    log "Loop stopping: no progress detected"
  fi

  if [ "$AFTER" -eq 0 ]; then
    log "All features complete!"
    break
  fi
done

# --- Summary ---
FINAL_PENDING=$(count_pending)
FINAL_COMPLETED=$(count_completed)
SESSIONS_RUN=$SESSION

echo ""
echo "========================="
echo "  SDD Loop Complete"
echo "========================="
echo "Sessions run:  $SESSIONS_RUN"
echo "Completed:     $FINAL_COMPLETED features"
echo "Remaining:     $FINAL_PENDING features"
echo "Log:           $PROJECT_DIR/$LOG_FILE"

if [ "$FINAL_PENDING" -eq 0 ]; then
  ok "All features complete!"
elif [ "$PROGRESS_MADE" = false ]; then
  warn "Stopped: no progress in last session (spec may need refinement)"
else
  info "Stopped: reached max-sessions limit ($MAX_SESSIONS)"
  info "Run again to continue: $0 --confirm --max-sessions N $PROJECT_DIR"
fi
