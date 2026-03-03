# Writ

Structured development primitives for Claude Code.

## The problem

AI coding agents are powerful but unreliable at scale. They overengineer, skip
verification, lose context across sessions, and mark things done without testing.
The longer the session, the worse it gets. If you've watched an agent confidently
commit broken code, or build a five-layer abstraction for a three-line change,
Writ was built for that problem.

## How Writ works

You write a spec with mechanically verifiable acceptance criteria. Claude
implements one feature at a time, verifies every criterion, and commits. State
persists in JSON across sessions so Claude reconstructs context from files rather
than memory. No custom infrastructure - just CLAUDE.md, slash commands, agents,
and git.

## Install

```bash
git clone https://github.com/robertdanco/writ /path/to/writ
```

Then install into any project:

```bash
cd your-project
/path/to/writ/init.sh
```

Or specify the directory directly:

```bash
/path/to/writ/init.sh /path/to/your/project
```

Add an alias to run `writ-init` from anywhere:

```bash
# Add to ~/.zshrc or ~/.bashrc
export WRIT_HOME="/path/to/writ"
alias writ-init="$WRIT_HOME/init.sh"
```

The installer is idempotent - safe to re-run.

## Quick start

### Option A: You have a PRD

```
/writ-ingest prd.md
# Review and approve the generated writ.json

/writ-session
# Claude implements the first feature, verifies it, and commits
```

### Option B: Starting from scratch

```
# In Claude Code:
"Use the writ-initializer agent to set up the project"
# Claude asks clarifying questions, scaffolds the project, generates writ.json

/writ-session
# Begin implementation
```

### Option C: Existing codebase (no PRD)

```
/writ-introspect
# Claude scans the codebase, discovers existing features, generates writ.json
# All discovered features are marked "completed" (the baseline)

/writ-ingest prd.md    # optional: add new features on top of the baseline
/writ-session          # start implementing pending features
```

## Key ideas

### Specs, not prompts

`writ.json` defines what each feature must do in terms a shell command can verify.
Each criterion has a type, a target, and an expected value. The type tells Claude
exactly how to check it: `file_contains` either finds the string or it doesn't.
No interpretation.

| Type | What it checks | `target` | `expected` |
|---|---|---|---|
| `file_exists` | File is present | File path | (empty) |
| `file_contains` | File has specific content | File path | String to find |
| `command_succeeds` | Command exits 0 | Shell command | (empty) |
| `test_passes` | Test command exits 0 | Test command | (empty) |
| `grep_match` | Pattern found in files | Directory or glob | Pattern |
| `json_path_check` | JSON file field has expected value | JSON file path | jq filter expression |

Without typed criteria, the model re-interprets what "verify" means on each run.
Six types, each with one evaluation method, avoids that.

### Mechanical verification

Every criterion resolves to an exit code. No LLM-as-judge. This is what makes
autonomous mode possible - `writ-loop.sh` can run sessions unattended because
"did it pass?" is a binary question with a binary answer.

### One feature per session

Each session starts fresh, loads only the files it needs, implements one feature,
verifies every criterion, and commits. Claude reads `writ.json`, `progress.json`,
and `git log` at the start to reconstruct where things stand. No memory of
previous sessions required.

### The session protocol

Every `/writ-session` runs five phases:

1. Explore - load state, check for stale safety tags, run a regression check on completed features
2. Plan - map the project shape, generate a plan with full criteria coverage
3. Execute - create a safety tag, implement one feature, stop
4. Verify - check every criterion; after 3 failures, offer to revert to the safety tag
5. Commit - structured commit, update progress.json, remove the safety tag

The regression check blocks new work when existing features are broken. The safety
tag means a failed session doesn't leave the codebase half-modified.

### Structured state

Three files carry continuity between sessions.

`writ.json` is the spec: features, priorities, dependencies, criteria. Frozen
before any code is written.

`progress.json` tracks session results keyed by feature ID. JSON rather than
Markdown because models corrupt free-form text, and because `writ-loop.sh` and
`/writ-status` can parse it without asking Claude to interpret it.

`git log` is the audit trail.

A feature in `writ.json` looks like this:

```json
{
  "id": "user-auth",
  "title": "User Authentication",
  "description": "A user can sign up, log in, and log out",
  "depends_on": [],
  "priority": 1,
  "status": "pending",
  "acceptance_criteria": [
    { "description": "Login route exists", "type": "file_exists",
      "target": "src/routes/auth.js", "expected": "" },
    { "description": "Login function is exported", "type": "file_contains",
      "target": "src/routes/auth.js", "expected": "export function login" },
    { "description": "Auth tests pass", "type": "test_passes",
      "target": "npm test -- --grep 'auth'", "expected": "" }
  ]
}
```

## Commands

| Command | What it does |
|---|---|
| `/writ-ingest <file>` | Two-phase PRD ingestion: parse features, then expand to verifiable criteria. Marks ambiguous requirements `[NEEDS CLARIFICATION]` before proceeding. |
| `/writ-introspect` | Brownfield analysis: scans an existing codebase, discovers features with user checkpoints, and generates a verified baseline `writ.json`. |
| `/writ-session [feature-id]` | Full session: regression check, feature selection, plan, implement, verify, commit. |
| `/writ-plan [feature-id]` | Plan only - runs Explore and Plan phases, stops before executing. Shows exactly what Claude would do before you commit to it. |
| `/writ-verify <feature-id>` or `--all` | Evaluate criteria mechanically. `--all` checks all completed features for regressions. Read-only. |
| `/writ-commit <feature-id>` | Structured commit and progress.json update. Called automatically by `/writ-session`. |
| `/writ-status` | Project dashboard: counts, progress bar, last session summary, next recommended feature. Read-only. |

## Agents

`writ-initializer` is for new projects. Give it a PRD and it asks clarifying
questions, scaffolds the project, and generates `writ.json`. It doesn't write
any implementation code.

```
"Use the writ-initializer agent to initialize this project"
```

`writ-coder` implements a single feature end-to-end: the full 5-phase protocol,
with scope constraints enforced and no ability to spawn subagents. Use it when
you want to hand off a feature completely.

```
"Use the writ-coder agent to implement feature user-auth"
```

## Autonomous mode

When your spec is solid and your criteria are reliable, `writ-loop.sh` runs
sessions automatically.

```bash
# Dry run - preview what would happen (default)
bash scripts/writ-loop.sh

# Run for real - sessions execute until all features complete or stuck
bash scripts/writ-loop.sh --confirm

# Cap sessions explicitly
bash scripts/writ-loop.sh --confirm --max-sessions 5

# Target a specific project directory
bash scripts/writ-loop.sh --confirm /path/to/project
```

Sessions stop when all features are complete, max sessions is reached, no
progress was made in the last session, or a session fails. Everything gets
logged to `writ-loop.log`.

Run a few interactive sessions first to validate your criteria. Vague criteria
will cause the loop to get stuck.

## CI integration

Export acceptance criteria as a standalone CI check script:

```bash
bash scripts/writ-export-checks.sh > ci-checks.sh
bash ci-checks.sh  # exits non-zero if any criterion fails
```

All 6 criterion types are supported. Use in any CI system:

```yaml
# GitHub Actions
- run: bash <(bash scripts/writ-export-checks.sh)
```

A starter workflow is at `templates/github-actions-writ.yml`. Copy it to
`.github/workflows/writ-checks.yml` to get CI running immediately.

## What gets installed

```
your-project/
├── CLAUDE.md                    # Writ Protocol section appended
├── writ.json                    # Feature specification (template)
├── progress.json                # Session state (template)
├── progress.md                  # Human-readable progress log (template)
├── scripts/
│   ├── writ-loop.sh              # Autonomous session runner
│   └── writ-export-checks.sh     # CI verification script generator
└── .claude/
    ├── commands/
    │   ├── writ-introspect.md    # /writ-introspect - Brownfield codebase analysis
    │   ├── writ-ingest.md        # /writ-ingest - PRD to writ.json
    │   ├── writ-status.md        # /writ-status - Progress dashboard
    │   ├── writ-plan.md          # /writ-plan - Preview plan without executing
    │   ├── writ-session.md       # /writ-session - Full session orchestrator
    │   ├── writ-verify.md        # /writ-verify - Acceptance criteria check
    │   └── writ-commit.md        # /writ-commit - Atomic commit + state update
    └── agents/
        ├── writ-initializer.md   # First-session scaffolding agent
        └── writ-coder.md         # Feature implementation agent
```
