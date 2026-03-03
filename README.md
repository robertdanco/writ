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

Or install into a specific directory without cd-ing first:

```bash
/path/to/writ/init.sh /path/to/your/project
```

**Recommended: add an alias** so you can run `writ-init` from anywhere:

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

The core artifact is `writ.json` - a contract that defines what each feature
must do in terms the model can verify mechanically. Each acceptance criterion
has a type, a target, and an expected value. The type tells Claude exactly how
to check it. There's no interpretation: `file_contains` either finds the string
or it doesn't.

| Type | What it checks | `target` | `expected` |
|---|---|---|---|
| `file_exists` | File is present | File path | (empty) |
| `file_contains` | File has specific content | File path | String to find |
| `command_succeeds` | Command exits 0 | Shell command | (empty) |
| `test_passes` | Test command exits 0 | Test command | (empty) |
| `grep_match` | Pattern found in files | Directory or glob | Pattern |
| `json_path_check` | JSON file field has expected value | JSON file path | jq filter expression |

Typed criteria also prevent a class of problem where the model interprets
ambiguous prose differently on each run. Six types, each with exactly one
evaluation method.

### Mechanical verification

Every criterion resolves to an exit code. No LLM-as-judge. An objective bit
that cannot be argued with. This is what makes autonomous mode possible:
`writ-loop.sh` can run sessions unattended because "did it pass?" has a
deterministic answer. Models are capable evaluators of their own work when you
give them the right question - and exit code 0 is the right question.

### One feature per session

Focus produces better code than breadth. Each session starts with a fresh
context window, loads exactly the files it needs, implements one feature,
verifies every criterion, and commits. State files (not memory) carry continuity
between sessions. Claude reconstructs context from `writ.json`, `progress.json`,
and `git log` at the start of each session - faster and more reliably than from
compacted summaries.

### The session protocol

Every `/writ-session` follows five phases:

1. **Explore** - Load state, check for stale safety tags, run regression check on existing features
2. **Plan** - Reconnaissance of project shape and conventions, generate a plan with full criteria coverage mapping
3. **Execute** - Create a safety tag, implement one feature, nothing more
4. **Verify** - Check every criterion mechanically. After 3 failures, option to revert to the safety tag
5. **Commit** - Structured commit, update progress.json, clean up safety tag

The regression check in Explore blocks new work on existing failures. The
safety tag in Execute gives you a clean rollback point. The structured commit
in Commit produces a git log that reads like a feature changelog.

### Structured state

Cross-session continuity comes from three files, not memory.

`writ.json` holds the spec - features, priorities, dependencies, and acceptance
criteria. It's frozen before any code is written.

`progress.json` tracks session results, keyed by feature ID. JSON over prose
because models corrupt Markdown more easily, and because `writ-loop.sh` and
`/writ-status` can parse it mechanically without LLM interpretation.

`git log` carries the audit trail. Every commit message follows a structured
format.

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

**`writ-initializer`** - For new projects or when no `writ.json` exists yet.
Reads a PRD, asks clarifying questions, scaffolds the project, and generates
`writ.json`. Does not implement features.

```
"Use the writ-initializer agent to initialize this project"
```

**`writ-coder`** - The feature implementation agent. Follows the full 5-phase
protocol, enforces anti-overengineering constraints, and cannot spawn subagents.
Use when you want to delegate a complete feature implementation as a bounded task.

```
"Use the writ-coder agent to implement feature user-auth"
```

## Autonomous mode

Once your spec is solid and your criteria are reliable, `writ-loop.sh` runs
sessions automatically - the pattern from Anthropic's C compiler case study.

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

Exit conditions: all features complete, max sessions reached, no progress
detected (same pending count before and after a session), or a session fails.
Each session is logged to `writ-loop.log`.

**When to use:** After running a few interactive sessions to validate your
criteria are reliable. Immature specs with vague criteria will get stuck.

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
