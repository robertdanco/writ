# SDD: Spec-Driven Development for Claude Code

A reusable harness that turns Claude Code into a spec-driven development system
using only native primitives: CLAUDE.md, slash commands, agent definitions, and git.

No custom infrastructure. No external orchestrators.

## Install

```bash
git clone https://github.com/robertdanco/sdd /path/to/sdd
```

Then install into any project:

```bash
cd your-project
/path/to/sdd/init.sh
```

Or install into a specific directory without cd-ing first:

```bash
/path/to/sdd/init.sh /path/to/your/project
```

**Recommended: add an alias** so you can run `sdd-init` from anywhere:

```bash
# Add to ~/.zshrc or ~/.bashrc
export SDD_HOME="/path/to/sdd"
alias sdd-init="$SDD_HOME/init.sh"
```

Then:
```bash
cd your-project
sdd-init
```

The installer is idempotent - safe to re-run.

## What gets installed

```
your-project/
├── CLAUDE.md                    # SDD Protocol section appended
├── spec.json                    # Feature specification (template)
├── progress.json                # Session state (template)
├── progress.md                  # Human-readable progress log (template)
├── scripts/
│   ├── sdd-loop.sh              # Autonomous session runner
│   └── sdd-export-checks.sh     # CI verification script generator
└── .claude/
    ├── commands/
    │   ├── sdd-introspect.md    # /sdd-introspect - Brownfield codebase analysis
    │   ├── sdd-ingest.md        # /sdd-ingest - PRD to spec.json
    │   ├── sdd-status.md        # /sdd-status - Progress dashboard
    │   ├── sdd-plan.md          # /sdd-plan - Preview plan without executing
    │   ├── sdd-session.md       # /sdd-session - Full session orchestrator
    │   ├── sdd-verify.md        # /sdd-verify - Acceptance criteria check
    │   └── sdd-commit.md        # /sdd-commit - Atomic commit + state update
    └── agents/
        ├── sdd-initializer.md   # First-session scaffolding agent
        └── sdd-coder.md         # Feature implementation agent
```

## Quick start

### Option A: You have a PRD

```
cd your-project
claude

/sdd-ingest prd.md
# Review and approve the generated spec.json

/sdd-session
# Claude implements the first feature, verifies it, and commits
```

### Option B: Starting from scratch

```
cd your-project
claude

# In Claude Code:
"Use the sdd-initializer agent to set up the project"
# Claude asks clarifying questions, scaffolds the project, generates spec.json

/sdd-session
# Begin implementation
```

### Option C: You have an existing codebase (no PRD)

```
cd your-project
claude

/sdd-introspect
# Claude scans the codebase, discovers existing features, generates spec.json
# All discovered features are cataloged as "completed" (the baseline)

/sdd-ingest prd.md    # optional: add new features on top of the baseline
/sdd-session          # start implementing pending features
```

## The 5-phase session protocol

Every `/sdd-session` follows this loop:

1. **Explore** - Load state, check for stale safety tags, run regression check.
2. **Plan** - Structured reconnaissance (project shape, utilities, conventions),
   generate plan with full criteria coverage mapping.
3. **Execute** - Create safety tag, implement one feature, nothing more.
4. **Verify** - Check every criterion mechanically. After 3 failures, option
   to revert to safety tag.
5. **Commit** - Structured commit, update progress.json, clean up safety tag.

## Commands

### `/sdd-introspect`

Brownfield codebase analysis. Discovers existing features from code, tests, and docs and
generates `spec.json` + `progress.json` that establish a verified baseline under SDD governance.

Six-phase process:
1. **Reconnaissance** - scans project structure and detects archetype (HTTP server, CLI, library, frontend, monorepo)
2. **Feature discovery** - archetype-driven: routes grouped by resource, CLI commands, public exports, or pages
3. **Behavioral scenarios** - derives "when I do X, I expect Y" from reading source code
4. **Criteria generation** - generates 3-7 verifiable criteria per feature with confidence indicators (HIGH/MEDIUM/LOW)
5. **Baseline verification** - runs all criteria mechanically; interactive resolution for any failures
6. **Output** - writes `spec.json` (all discovered features as `completed`) and `progress.json`

Three mandatory user checkpoints: feature list, behavioral scenarios, and criteria review.

All brownfield features are written as `status: "completed"` so that:
- `/sdd-verify --all` includes them in regression checks
- `/sdd-session` skips them during feature selection
- `sdd-loop.sh` counts them correctly in progress.json

Use `/sdd-ingest` afterward (merge mode) to add new features on top of the baseline.

### `/sdd-status`

Instant project dashboard. Shows total/done/pending/blocked feature counts, progress bar,
last session summary, next recommended feature, and dependency chain. Read-only.

Use at any time to orient yourself without starting a full session.

### `/sdd-plan [feature-id]`

Generate a concrete implementation plan without writing any code. Runs the Explore and
Plan phases of the 5-phase loop and stops before executing.

Use this to:
- Review what Claude would do before committing to a session
- Check feasibility of a feature
- Preview the implementation approach for a complex feature

Output ends with: `"Plan complete. Run /sdd-session <feature-id> to implement."`

### `/sdd-ingest <file-or-url>`

Two-phase PRD ingestion:
- Phase 1: Parse PRD into draft feature list, present for review
- Phase 2: Expand features with specific, verifiable acceptance criteria

Writes `spec.json` to the project root.

Ambiguous requirements are marked `[NEEDS CLARIFICATION]` and must be resolved
before criteria generation. If the project has a linter configured, lint
criteria are automatically included. Features spanning 8+ files are flagged
with `[SPLIT?]` for decomposition.

### `/sdd-session [feature-id]`

Primary entry point for all development. Runs the full 5-phase loop.

Optionally pass a feature ID to work on a specific feature instead of auto-selecting.

### `/sdd-verify <feature-id>` or `/sdd-verify --all`

Evaluates acceptance criteria mechanically. Does not modify files.

Run `--all` to check all completed features for regressions.

### `/sdd-commit <feature-id>`

Creates a structured commit and updates progress.json. Called automatically
by `/sdd-session` after successful verification.

## spec.json structure

```json
{
  "project": "My App",
  "features": [
    {
      "id": "user-auth",
      "title": "User Authentication",
      "description": "A user can sign up, log in, and log out",
      "depends_on": [],
      "priority": 1,
      "status": "pending",
      "acceptance_criteria": [
        {
          "description": "Login route exists",
          "type": "file_exists",
          "target": "src/routes/auth.js",
          "expected": ""
        },
        {
          "description": "Login function is exported",
          "type": "file_contains",
          "target": "src/routes/auth.js",
          "expected": "export function login"
        },
        {
          "description": "Auth tests pass",
          "type": "test_passes",
          "target": "npm test -- --grep 'auth'",
          "expected": ""
        }
      ]
    }
  ]
}
```

### Criterion types

| Type | What it checks | `target` | `expected` |
|---|---|---|---|
| `file_exists` | File is present | File path | (empty) |
| `file_contains` | File has specific content | File path | String to find |
| `command_succeeds` | Command exits 0 | Shell command | (empty) |
| `test_passes` | Test command exits 0 | Test command | (empty) |
| `grep_match` | Pattern found in files | Directory or glob | Pattern |
| `json_path_check` | JSON file field has expected value | JSON file path | jq filter expression |

All criteria are mechanically verifiable - no subjective assessments.

For `json_path_check`, the `expected` field is a jq filter expression that must return truthy:
```json
{ "type": "json_path_check", "target": "package.json", "expected": ".version == \"2.0.0\"" }
{ "type": "json_path_check", "target": "config.json", "expected": ".database.host != null" }
{ "type": "json_path_check", "target": "manifest.json", "expected": ".permissions | length > 0" }
```

## progress.json structure

Keyed by feature ID for O(1) lookup and clean git diffs:

```json
{
  "last_session": {
    "date": "2026-03-01T14:00:00Z",
    "feature_id": "user-auth",
    "summary": "Implemented JWT-based auth with login and logout routes",
    "next_recommended": "user-profile"
  },
  "user-auth": {
    "status": "completed",
    "started_at": "2026-03-01T13:00:00Z",
    "completed_at": "2026-03-01T14:00:00Z",
    "commit_hash": "abc1234",
    "sessions": 1,
    "criteria_results": {
      "Login route exists": true,
      "Login function is exported": true,
      "Auth tests pass": true
    }
  }
}
```

## Agents

### `sdd-initializer`

Use for brand-new projects or when no `spec.json` exists yet. Reads a PRD,
asks clarifying questions, scaffolds the project, generates spec.json, and
writes `init.sh`. Does NOT implement features.

Invoke from Claude Code: `"Use the sdd-initializer agent to initialize this project"`

### `sdd-coder`

The feature implementation agent. Follows the full 5-phase protocol, enforces
anti-overengineering constraints, and cannot spawn subagents. Use when you want
to delegate a complete feature implementation as a bounded task.

Invoke from Claude Code: `"Use the sdd-coder agent to implement feature user-auth"`

## Autonomous mode

Once your spec is solid and your acceptance criteria are reliable, `sdd-loop.sh`
runs sessions automatically - the pattern from Anthropic's C compiler case study.

```bash
# Dry run - preview what would happen (default)
bash scripts/sdd-loop.sh

# Run for real - sessions execute until all features complete or stuck
bash scripts/sdd-loop.sh --confirm

# Cap sessions explicitly
bash scripts/sdd-loop.sh --confirm --max-sessions 5

# Target a specific project directory
bash scripts/sdd-loop.sh --confirm /path/to/project
```

Exit conditions: all features complete, max sessions reached, no progress detected
(same pending count before and after a session), or a session fails.

Each session is logged to `sdd-loop.log` with timestamps.

**When to use:** After running a few interactive sessions to validate your criteria
are reliable. Immature specs with vague criteria will get stuck.

## CI verification

Export your acceptance criteria as a standalone CI check script:

```bash
# Generate a self-contained check script
bash scripts/sdd-export-checks.sh > ci-checks.sh

# Run it (exits non-zero if any criterion fails)
bash ci-checks.sh
```

The generated script checks all completed features against their criteria
using the same evaluation logic as `/sdd-verify`. All 6 criterion types are
supported. Unknown types produce a SKIP warning, not a silent pass.

Use in any CI system:
```yaml
# GitHub Actions example
- run: bash <(bash scripts/sdd-export-checks.sh)
```

## Design principles

This harness is built on 13 principles synthesized from Anthropic's engineering
documentation. The key ones:

- **One feature per session** - Focus produces better code than breadth
- **Verify before commit** - Never mark complete without mechanical verification
- **JSON for state, Markdown for notes** - Models are less likely to corrupt JSON
- **Lean CLAUDE.md (~50 lines)** - Details in commands loaded on demand
- **6 criterion types** - All mechanically verifiable, no subjective criteria
- **Dual-prompt architecture** - Initializer (expansive) vs. coder (constrained)
- **Regression check first** - Block new work on existing failures

## After installation

1. Fill in your build/test/start commands in `CLAUDE.md` under "Build and test commands"
2. Either run `/sdd-ingest` with your PRD (Option A), use the `sdd-initializer` agent (Option B),
   or run `/sdd-introspect` to establish a baseline from an existing codebase (Option C)
3. Run `/sdd-session` for each feature - that's the whole workflow
