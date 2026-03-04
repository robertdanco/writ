#!/usr/bin/env bash
# writ-loop.sh - Run Writ sessions autonomously until all features complete
# Usage: ./writ-loop.sh [--confirm] [--max-sessions N] [project-dir]
#
# By default runs in dry-run mode. Pass --confirm to actually execute.
# Pattern from Anthropic's C compiler case study (16 parallel agents, $20K, 100K LOC in 2 weeks).

set -euo pipefail

# --- Defaults ---
CONFIRM=false
MAX_SESSIONS=""
PROJECT_DIR="$(pwd)"
LOG_FILE="writ-loop.log"

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

# --- Pre-flight ---
if ! command -v claude >/dev/null 2>&1; then
  err "claude CLI not found in PATH"
  exit 1
fi

# --- Validate ---
if [ ! -f "$PROJECT_DIR/writ.json" ]; then
  err "No writ.json found in $PROJECT_DIR"
  err "Run /writ-ingest first to generate a spec, then use writ-loop."
  exit 1
fi

# Count pending features using python (avoids jq dependency)
count_completed() {
  # Read from progress.json (authoritative) not writ.json (may lag behind)
  python3 -c "
import json, os
p_file = '$PROJECT_DIR/progress.json'
if not os.path.exists(p_file):
    print(0)
else:
    with open(p_file) as f:
        p = json.load(f)
    features = p.get('features', p)  # handle both {features:{...}} and flat {id:{...}}
    if isinstance(features, dict):
        done = [v for v in features.values() if isinstance(v, dict) and v.get('status') == 'completed']
        print(len(done))
    else:
        print(0)
" 2>/dev/null || echo "0"
}

count_pending() {
  python3 -c "
import json, os
s_file = '$PROJECT_DIR/writ.json'
p_file = '$PROJECT_DIR/progress.json'
with open(s_file) as f:
    spec = json.load(f)
total = len(spec.get('features', []))
# completed = progress.json entries with status completed
completed = 0
if os.path.exists(p_file):
    with open(p_file) as f:
        p = json.load(f)
    features = p.get('features', p)
    if isinstance(features, dict):
        completed = sum(1 for v in features.values() if isinstance(v, dict) and v.get('status') == 'completed')
print(total - completed)
" 2>/dev/null || echo "0"
}

get_project_name() {
  python3 -c "
import json
with open('$PROJECT_DIR/writ.json') as f:
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
echo "Writ Autonomous Loop"
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
  err "No git repository found. Writ requires git for state management."
  exit 1
fi

GIT_STATUS=$(git -C "$PROJECT_DIR" status --porcelain -uno 2>/dev/null || echo "ERROR")
if [ "$GIT_STATUS" = "ERROR" ]; then
  err "git status failed in $PROJECT_DIR"
  exit 1
fi
if [ -n "$GIT_STATUS" ]; then
  warn "Uncommitted changes detected:"
  git -C "$PROJECT_DIR" status --short -uno
  echo ""
  read -r -p "Continue anyway? (y/N) " REPLY
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    info "Aborted. Commit or stash changes before running writ-loop."
    exit 1
  fi
fi

# --- Main loop ---
SESSION=0
PROGRESS_MADE=true

log "=== Writ loop started: project=$PROJECT, pending=$PENDING, max=$MAX_SESSIONS ==="

while [ "$SESSION" -lt "$MAX_SESSIONS" ] && [ "$PROGRESS_MADE" = true ]; do
  SESSION=$((SESSION + 1))
  BEFORE=$(count_pending)

  log "--- Session $SESSION/$MAX_SESSIONS starting (pending: $BEFORE) ---"
  info "Session $SESSION/$MAX_SESSIONS..."

  # Run session in project directory
  # --dangerously-skip-permissions avoids interactive prompts in non-interactive mode
  ABS_LOG="$(cd "$PROJECT_DIR" && pwd)/$LOG_FILE"
  if ! (cd "$PROJECT_DIR" && claude --print --dangerously-skip-permissions "/writ-session --auto" 2>>"$ABS_LOG"); then
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
echo "  Writ Loop Complete"
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
