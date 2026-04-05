---
description: Interactive spec co-creation with codebase awareness - generate change-level features for writ.json
allowed-tools: Read, Glob, Grep, Bash, Write, Edit
---

Co-create a change-level spec for a brownfield codebase. Takes a one-sentence problem
statement and walks through structured conversation rounds to produce a writ.json
feature entry with acceptance criteria and advisory scope.

This replaces `/writ-ingest` for brownfield projects where you're adding features to
an existing codebase rather than implementing a full PRD from scratch.

Arguments: `$ARGUMENTS`
- A problem statement string: `"add CSV export for activity log"`
- `--amend <feature-id>` - modify an existing feature's criteria
- `--resume` - continue from `.writ/spec-session.json`

## Step 1: Load context

### Profile-aware mode

Read `.writ/profile.json`. If it exists:
- Note project name, language, framework, entry points, shared modules
- Read `.writ/test-map.json` for test mappings
- This is "profile-aware mode" - use the profile throughout for file lookups

### Degraded mode

If `.writ/profile.json` does NOT exist:
- Output: "No codebase profile found. Running in degraded mode - codebase exploration will be manual. For better results, run /writ-profile first."
- Fall back to: Glob the source tree, read package manifest (package.json, pyproject.toml, Cargo.toml, go.mod), read CLAUDE.md for build/test/start commands

### Existing spec

Read `writ.json` if it exists. Note existing features to avoid duplicates and to
set `depends_on` for new features.

### Resume mode

If `$ARGUMENTS` contains `--resume`:
- Read `.writ/spec-session.json`. If it does not exist: "No spec session to resume. Start a new one with /writ-spec \"description\"."
- Do NOT attempt to reconstruct the conversation. Present a summary of prior decisions:
  ```
  Resuming spec session for: "<problem statement>"
  Previous decisions:
    Round 1: <decision summary>
    Round 2: <decision summary>
    Round 3: <decision summary>
  Draft feature: <id> with N criteria

  Options:
  1. Continue refining criteria
  2. Accept current spec and write to writ.json
  3. Start fresh (discard previous session)
  ```
- Wait for user response.
- If option 1: proceed to Step 5.
- If option 2: proceed to Step 6 using the draft feature from the session file.
- If option 3: proceed to Step 2.

### Amend mode

If `$ARGUMENTS` contains `--amend <feature-id>`:
- Read `writ.json`, find the specified feature. If not found: "Feature '<id>' not found in writ.json."
- Check for `.writ/runs/<feature-id>/suggestions.json`. This file is produced by the smart criterion suggestion subagent (Phase 3, enhanced writ-verify).
  - If suggestions exist: load them and present alongside current criteria.
  - If no suggestions file: "No automated suggestions found. You can add or modify criteria manually."
- Present current criteria with numbering.
- If suggestions exist, present each with `[accept/reject]` prompt.
- User can also add, modify, or remove criteria manually.
- After user is done: write updated criteria back to writ.json and stop.

## Step 2: Understand the problem (Round 1)

Parse the problem statement from `$ARGUMENTS`. If no problem statement and not `--resume`
or `--amend`: "No problem statement provided. Usage: `/writ-spec \"add CSV export for activity log\"`. Why: writ-spec needs a starting point to co-create the spec. Fix: provide a one-sentence description of what you want to build." Stop.

### Profile-aware exploration

Search `profile.json` for relevant files:
- Check `files[].path` and `files[].exports` for keywords from the problem statement
- Follow `dependency_graph` edges from matching files to find the neighborhood
- Check `test-map.json -> source_to_tests` for existing test coverage of those files
- Read the 3-5 most relevant source files to understand the current implementation

### Degraded exploration

Glob and Grep for files related to keywords in the problem statement.
Read package manifest for project structure. Read the 3-5 most relevant files.

### Present findings

```
Here's how the relevant area works:

Files involved:
  src/routes/activity.ts - handles /api/activity endpoints (exports: getActivity, listActivities)
  src/models/activity.ts - Activity model (exports: Activity, ActivityQuery)
  src/utils/format.ts - shared formatting utilities

Dependency chain: routes/activity.ts -> models/activity.ts -> db/client.ts
Existing tests: tests/routes/activity.test.ts (covers getActivity, listActivities)

Is this the right area? Is this the right problem to solve, or should we scope differently?
```

Wait for user response.

### PM brain behaviors (Round 1)

- If the problem seems too large for one feature (would touch 8+ files or need 7+ criteria): suggest scoping down. "This seems like it could be split into smaller pieces. Would it make sense to start with just X?"
- If the problem is too vague to identify relevant files: ask a specific clarifying question rather than guessing. "I found several areas that could relate to this. Can you clarify: do you mean X or Y?"
- If the problem overlaps with an existing feature in writ.json: flag it. "Feature '<id>' already covers <description>. Is this an extension of that, or a separate concern?"

## Step 3: Propose approaches (Round 2)

Based on user confirmation or correction from Round 1, propose 2-3 approaches
scoped to the delta (what changes relative to the current codebase):

```
Approach A: Add CSV endpoint to existing activity router
  Files: modify src/routes/activity.ts, create src/utils/csv.ts
  Tests: modify tests/routes/activity.test.ts
  Effort: Low | Risk: Low | Test impact: 1 test file

Approach B: Create dedicated export module with format pluggability
  Files: create src/export/csv.ts, src/export/index.ts, modify src/routes/activity.ts
  Tests: create tests/export/csv.test.ts
  Effort: Medium | Risk: Low | Test impact: 2 test files

Which direction? (Or describe a different approach)
```

In profile-aware mode, derive file lists from `dependency_graph` and `files` inventory.
In degraded mode, estimate based on the files read in Round 1.

Wait for user response.

### PM brain behaviors (Round 2)

- Flag if an approach touches files in `shared_modules` (from profile): "Note: Approach B modifies src/utils/ which is imported by 12 other files. Changes here have wider blast radius."
- Note if an approach modifies files with no existing test coverage (from test-map): "src/routes/activity.ts has no test file in the test map. You may want to add test_passes criteria."
- If both approaches seem equivalent, have an opinion: recommend the simpler one and explain why.

## Step 4: Co-create criteria (Round 3)

Based on the chosen approach, generate 3-7 acceptance criteria.

### Criteria generation rules (same as writ-ingest)

- Every feature SHOULD have at least one behavioral criterion (`command_succeeds` or `test_passes`)
- Exception: pure config/data features where `json_path_check`/`file_contains` fully verify
- If the project has a linter or formatter configured (check CLAUDE.md, package.json scripts): include a `command_succeeds` criterion for linting on every feature that creates or modifies source files
- Be specific: actual file paths from the profile, real endpoint names, concrete values
- Use all 6 criterion types appropriately:
  - `command_succeeds` - runtime behavior, CLI output, API endpoints, e2e
  - `test_passes` - existing test suites or new tests for this feature
  - `file_exists` - scaffolding, new files, build output
  - `file_contains` - config values, generated content, specific code patterns
  - `json_path_check` - API responses, config validation, structured output
  - `grep_match` - code conventions, imports, cross-file consistency
- 3-7 criteria per feature
- For HTTP servers, use the lifecycle pattern: `bash -c "<start> & sleep 2 && <check> ; kill %1"`
- For `grep_match` and `file_contains`: never use patterns starting with `--`
- For file paths with shell glob characters: always quote

### Present criteria

```
Acceptance criteria:

1. [file_exists] src/utils/csv.ts
   -> Verifies the CSV utility module is created

2. [command_succeeds] bash -c "node src/server.js & sleep 2 && curl -s localhost:3000/api/activity/export?format=csv | head -1 | grep -q 'id,timestamp,action' ; kill %1"
   -> Verifies CSV export endpoint returns correct headers

3. [test_passes] npm test -- --grep "csv export"
   -> Verifies test coverage for the new feature

4. [file_contains] src/routes/activity.ts -> "/export"
   -> Verifies the export route is registered

Anything missing? Any criterion feel wrong?
```

Wait for user response.

### PM brain behaviors (Round 3)

- Push back on untestable criteria: "That criterion is untestable because [reason]. Here's a testable version: [alternative]."
- Flag missing edge cases: "What about when the activity log is empty? Should the CSV export return just headers, or an error?"
- Suggest stronger criterion types: "Instead of just `file_exists` for src/utils/csv.ts, consider a `command_succeeds` that actually imports and calls the module to verify it works."
- Challenge weak criteria: "This `file_contains` check for '/export' would also match existing code. Use a more specific pattern."
- If all criteria are `file_exists`/`file_contains`: "These criteria only check static file content. Consider adding a behavioral criterion (`command_succeeds` or `test_passes`) that verifies the feature actually works at runtime."

## Step 5: Refine (Rounds 4-5)

Iterate on user feedback. Present updated criteria after each round of changes.

- Model can push back on requests ("Adding that criterion would make the feature untestable in CI because it requires a database connection. Here's an alternative that uses a test database.")
- Model can suggest additions ("Based on the dependency graph, this change also affects src/middleware/auth.ts. Should we add a criterion to verify auth still works?")
- Maximum 5 total rounds. If user says "looks good", "that's fine", "ship it", or equivalent: proceed to Step 6.

## Step 6: Write spec

### Generate feature ID

Derive a kebab-case ID from the title (e.g., "CSV Export for Activity Log" -> `csv-export-activity-log`).
Check `writ.json` for collisions. If collision: append `-2` (or ask user for alternative).

### Assemble feature object

```json
{
  "id": "<kebab-case-id>",
  "title": "<short title from discussion>",
  "description": "<user perspective description>",
  "depends_on": ["<existing feature IDs if applicable>"],
  "priority": 2,
  "status": "pending",
  "scope": {
    "files": ["<files to modify or create, from chosen approach>"],
    "tests": ["<test files to run, from test-map + approach>"]
  },
  "acceptance_criteria": [
    {
      "description": "<human-readable description>",
      "type": "<one of 6 types>",
      "target": "<file path or command>",
      "expected": "<expected value or empty string>"
    }
  ]
}
```

The `scope` field is ADVISORY. Downstream verification uses `git diff` + test-map for
actual impact, not these predictions. Scope is useful for `/writ-diff` previews and
for `/writ-session` planning, but is never authoritative.

### Merge into writ.json

- If `writ.json` exists with features: append the new feature to the `features` array.
  Set `depends_on` based on the discussion and existing feature relationships.
- If `writ.json` exists but has only the template placeholder (`example-feature`):
  replace the features array entirely.
- If `writ.json` does not exist: create it with project metadata from the profile
  (or manifest), version `"1.0.0"`, current ISO timestamp, and this feature.

Validate the JSON after writing:
```bash
python3 -c "import json; json.load(open('writ.json'))"
```

### Update progress.json

If `progress.json` exists, update `last_session.next_recommended` to the new feature ID.
If it does not exist, create it from the template with `next_recommended` set.

## Step 7: Persist and summarize

### Write spec-session.json

Write `.writ/spec-session.json` for resume capability and audit trail:

```json
{
  "version": "1.0.0",
  "started_at": "<ISO timestamp of session start>",
  "completed_at": "<ISO timestamp of completion>",
  "problem_statement": "<original input from $ARGUMENTS>",
  "feature_id": "<generated feature ID>",
  "rounds": [
    { "round": 1, "decision": "<what was confirmed or changed about the problem>" },
    { "round": 2, "decision": "<which approach was chosen and why>" },
    { "round": 3, "decision": "<criteria as approved, noting any changes from initial proposal>" }
  ],
  "profile_mode": "aware|degraded",
  "draft_feature": {
    "<<full feature object as written to writ.json>>"
  }
}
```

### Output summary

```
=== Spec Complete ===

Feature: <id> - <title>
Criteria: N acceptance criteria
Scope: M files, L tests (advisory)
Priority: P

Added to writ.json.

Next steps:
  /writ-diff <feature-id>    Preview impact before implementing
  /writ-session <feature-id> Start implementation
  /writ-spec "another thing" Add another feature
```

## Error handling

All errors must include: what happened, why, and how to fix.

| Condition | Message |
|-----------|---------|
| No problem statement (and not --resume/--amend) | "No problem statement provided. Usage: `/writ-spec \"add CSV export for activity log\"`. Why: writ-spec needs a starting point to co-create the spec. Fix: provide a one-sentence description of what you want to build." |
| No profile AND no source files found | "Cannot find source files and no codebase profile exists. Why: writ-spec needs to understand your codebase to generate useful criteria. Fix: run /writ-profile first, or ensure you're in the project root." |
| Feature ID collision | "Feature '<id>' already exists in writ.json. Why: feature IDs must be unique. Fix: the new feature will use '<id>-2' instead, or suggest a different name." |
| --resume but no spec-session.json | "No spec session to resume. Why: .writ/spec-session.json does not exist. Fix: start a new session with /writ-spec \"description\"." |
| --amend but feature not found | "Feature '<id>' not found in writ.json. Why: --amend requires an existing feature. Fix: check the feature ID with /writ-status, or create it first with /writ-spec." |
