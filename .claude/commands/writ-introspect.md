---
description: Brownfield codebase analysis - discover existing features and generate writ.json for Writ governance
allowed-tools: Read, Glob, Grep, Bash, Write
---

Analyze the existing codebase and generate `writ.json` + `progress.json` that catalog what already works, enabling Writ governance over an established project.

## Phase 1: Reconnaissance (read-only)

### Step 1: Check existing state

Read `writ.json` if it exists. If it has features, ask:
"writ.json already exists with N features. Merge introspected features (preserving existing), replace, or abort?"
Wait for user response before proceeding.

### Step 2: Scan project structure

Read in order:
- `CLAUDE.md` (build/test/start commands if present)
- Package manifest: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`, `pom.xml` (whichever exists)
- `README.md`, `CHANGELOG.md`
- Any files under `docs/`
- Glob the source tree to understand layout: `src/**/*`, `lib/**/*`, `app/**/*`, etc.

### Step 3: Detect archetype

Classify the project as one of: **HTTP server**, **CLI tool**, **library**, **frontend app**, **monorepo**, or **other**.

Detection signals:

| Archetype | Detection signals |
|-----------|------------------|
| HTTP server | express/fastapi/gin/actix/rails routes, `listen(`, Dockerfile with EXPOSE |
| CLI tool | commander/argparse/clap/cobra patterns, `bin` field in package.json, `#[command]` |
| Library | `index.js`/`__init__.py`/`lib.rs` as entry, no server/CLI entry point, primarily exports |
| Frontend app | framework files (next.config.js, vite.config.js, svelte.config.js), `public/`, JSX/TSX routes |
| Monorepo | multiple package manifests at different directory levels (`packages/`, `apps/`, `services/`) |

### Step 4: Monorepo check

If monorepo detected, list the discovered services/packages and ask:
"Which service should I introspect? (Or 'all' for a top-level view)"
Scope all subsequent discovery to the selected subtree.

## Phase 2: Feature Discovery (read-only)

### Step 5: Archetype-driven discovery

Use the archetype to focus discovery:

| Archetype | Primary discovery targets |
|-----------|--------------------------|
| HTTP server | Route registrations - group by resource (users, posts, auth, etc.). Look for `app.get`, `router.post`, `@app.route`, `r.Handle`, etc. |
| CLI tool | Command registrations - `.command()`, `add_parser()`, `#[command]`, `cobra.Command{}` |
| Library | Public exports from the entry file - exported functions, classes, types |
| Frontend app | Route definitions, page/view components, layout files |

For each logical group of routes/commands/exports, propose one feature.
A feature = one user-observable behavior. Do not create one feature per route - group by resource or capability.
Flag any feature that appears to span 8+ files or would need 7+ criteria with `[SPLIT?]`.

### Step 6: Enrich from tests

Glob for test files: `**/*.test.*`, `**/*.spec.*`, `**/test_*`, `**/tests/**`.
Read a representative sample (not all files - focus on describe/it block names).
Map test coverage to discovered features. Note which features have test coverage.

### Step 7: Detect abandoned work

Grep for: `TODO`, `FIXME`, `HACK`, `XXX`, commented-out route/command handlers.
Collect these separately - they do NOT become features but are reported to the user.

---

**CHECKPOINT 1: Confirm feature list**

Present:
```
Discovered N features from codebase:

Source: code
  - <proposed-id>: <title> [tests: yes/no]
  - <proposed-id>: <title> [tests: yes/no]

Source: tests only
  - <proposed-id>: <title>

Source: docs only
  - <proposed-id>: <title>

Partial / abandoned (not becoming features):
  - <description of abandoned work>

Does this list look right? Add, remove, split, or merge any features before I continue.
```

Wait for user confirmation. Revise if requested.

## Phase 3: Behavioral Scenarios

### Step 8: Establish verification context

Without running the project, discover how it is invoked from code:
- Check `package.json` scripts, `Makefile` targets, `Dockerfile` CMD/ENTRYPOINT
- Read the main entry file to find the startup sequence
- Check for `CLAUDE.md` build/test/start commands (use these if present)

---

**CHECKPOINT 2: Confirm behavioral scenarios**

For each confirmed feature, propose a concrete "when I do X, I expect Y" based on reading the source code.
Use specific values: actual endpoints, real flag names, concrete inputs and outputs.
Mark anything uncertain with `[NEEDS CLARIFICATION]`.

```
Before generating criteria, confirm what "working" looks like for each feature.
I've derived these scenarios from the code - correct anything wrong and fill in gaps:

1. <feature-id>: <concrete scenario with specific inputs and expected outputs>
   [NEEDS CLARIFICATION: <targeted question about a gap, if any>]

2. <feature-id>: <concrete scenario>
...
```

Wait for user feedback. Revise scenarios based on their answers.
All `[NEEDS CLARIFICATION]` markers must be resolved before proceeding to
criteria generation. Do not guess - ask.

## Phase 4: Criteria Generation

### Step 9: Generate criteria per feature

Rules (same as writ-ingest):
- Every feature MUST have at least one behavioral criterion (`command_succeeds` or `test_passes`)
- If the project has a linter or formatter configured, include a
  `command_succeeds` criterion running the lint command on every feature
  that creates or modifies source files.
- If existing tests cover the feature, include `test_passes` pointing at them
- For HTTP servers, use the lifecycle pattern: `bash -c "<start> & sleep 2 && <check> ; kill %1"`

- 3-7 criteria per feature
- Be specific: actual file paths, real endpoint names, concrete values

**Baseline confidence:**
- **HIGH** = feature confirmed by code + tests + docs
- **MEDIUM** = feature confirmed by code only (no tests or docs)
- **LOW** = feature confirmed by tests or docs only (code not obviously present)

---

**CHECKPOINT 3: Confirm criteria**

Present per feature:
```
Feature: <id> - <title>  [Confidence: HIGH/MEDIUM/LOW]
Criteria:
  1. [command_succeeds] <target>
     → <what this verifies>
  2. [test_passes] <target>
     → <what this verifies>
  3. [file_exists] <target>
     → <what this verifies>
Discrimination: <why at least one criterion would FAIL if this feature were absent>

Feature: <next-id> ...
```

Ask: "Any criteria to adjust before I run baseline verification?"
Wait for user response.

## Phase 5: Baseline Verification

### Step 10: Run every criterion mechanically

Evaluate each criterion using the same logic as writ-verify:

| Criterion type | Verification method |
|---|---|
| `file_exists` | `test -f <target> && echo PASS \|\| echo FAIL` |
| `file_contains` | `grep -qF "<expected>" "<target>" && echo PASS \|\| echo FAIL` |
| `command_succeeds` | Run `<target>`, check exit code 0 = PASS |
| `test_passes` | Run `<target>` as shell command, check exit code 0 = PASS |
| `grep_match` | `grep -r "<expected>" <target> > /dev/null 2>&1 && echo PASS \|\| echo FAIL` |
| `json_path_check` | `jq -e '<expected>' '<target>' > /dev/null 2>&1 && echo PASS \|\| echo FAIL` |

Do not dump full command output. Write verbose output to `/tmp/writ-introspect-verify.txt` if needed.

Report results per feature:
```
Feature: <id> - <title>
  [PASS] <criterion description>
  [FAIL] <criterion description>
  ...
Status: PASS (N/N) | PARTIAL (N/M) | FAIL (0/N)
```

### Step 11: Handle failures interactively

If any criterion fails, present options per feature:
```
Feature <id> has N failing criteria:
  [FAIL] <criterion description>
  Command: <target>

Options:
  1. Fix the criterion (the command is wrong - let me correct it)
  2. Drop the failing criterion (keep feature with remaining criteria)
  3. Exclude this feature entirely (add later via /writ-ingest)
  4. Mark this feature as "pending" instead of "completed"
```

Wait for user choice per failing feature. Apply corrections and re-verify if option 1 is chosen.

## Phase 6: Write Output

### Step 12: Write writ.json

All features passing verification get `status: "completed"`.
Features the user chose to mark pending get `status: "pending"`.

Assign priorities 1-5:
- 1 = foundational (other features depend on it, or it's the core capability)
- 2-3 = main features
- 4-5 = optional / polish

Build `depends_on` from import relationships and middleware chains observed during discovery.

Use the project name from the package manifest or README. Set `version: "1.0.0"` and `created_at` to current ISO timestamp.


### Step 13: Write progress.json

For every feature with `status: "completed"`, add an entry.
Get the current HEAD commit hash with `git rev-parse --short HEAD`.

Entry format for brownfield features:
```json
"<feature-id>": {
  "status": "completed",
  "started_at": "",
  "completed_at": "<ISO timestamp>",
  "commit_hash": "<current HEAD>",
  "sessions": 0,
  "criteria_results": {
    "<criterion description>": true,
    ...
  }
}
```

`sessions: 0` and empty `started_at` mark these as pre-existing, not Writ-built.

Set `last_session`:
```json
"last_session": {
  "date": "<ISO timestamp>",
  "feature_id": "",
  "summary": "Baseline established via /writ-introspect: N features cataloged",
  "next_recommended": "<first pending feature id, or empty if none>"
}
```

If `progress.json` already exists (merge mode), add entries for new features only. Do not overwrite existing entries.

### Step 14: Append to progress.md

If `progress.md` exists, append one line:
`- [<YYYY-MM-DD>] BASELINE: N features introspected via /writ-introspect`

### Step 15: Output summary

```
=== Introspection Complete ===

Project: <name>
Archetype: <type>

Features cataloged: N
  Completed (verified): X
  Pending (chosen by user): Y
  Excluded: Z

Abandoned work noted: M items (not in spec)

Files written:
  writ.json    - N features
  progress.json - X entries

Next steps:
  /writ-verify --all      Confirm full baseline
  /writ-ingest <prd>      Add new features (merge mode)
  /writ-session            Start implementing pending features
```

## Edge case handling

| Case | Behavior |
|------|----------|
| Empty or skeleton codebase (< 2 features found) | Report "Too few features to introspect. Use /writ-ingest or the writ-initializer agent instead." Stop. |
| Monorepo | Ask which service at Step 4. Scope discovery to that subtree. |
| No tests at all | Generate only `command_succeeds` + `file_exists` criteria. Note the absence in the summary. |
| Extensive tests, no docs | Use test describe/it block hierarchy as the primary feature source. |
| Library with no entry point | Use `test_passes` + `file_contains` (export checks). No `command_succeeds` criteria. |
| Frontend / static site | Use build output verification: `npm run build && test -f dist/index.html` |
| Half-implemented feature | Exclude by default. Report as "partial - consider adding via /writ-ingest after completing." |
| Abandoned code (TODO, commented-out) | Report but do not generate features. |
