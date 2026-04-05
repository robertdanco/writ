---
description: Show files and tests affected by a feature before implementation - pre-implementation impact preview
allowed-tools: Read, Glob, Grep, Bash
---

Show which files and tests a feature will affect before you start implementing it.
Reads `.writ/profile.json` and `.writ/test-map.json` to compute impact. Read-only.

Arguments: `$ARGUMENTS` = feature ID (required)

## Step 1: Load state

Read `.writ/profile.json`. If not found:
"No codebase profile found. Why: /writ-diff needs the dependency graph and test mappings to show impact analysis. Fix: run /writ-profile first, then re-run /writ-diff <feature-id>."
Stop.

Read `.writ/test-map.json`. If not found: same error as above.

Read `writ.json`. If not found:
"No writ.json found. Why: /writ-diff needs a feature spec to analyze. Fix: run /writ-spec or /writ-ingest first."
Stop.

## Step 2: Look up feature

Find the feature matching `$ARGUMENTS` in `writ.json`.

If not found:
"Feature '<id>' not found in writ.json. Available features:"
List all feature IDs with their titles and statuses. Stop.

Extract from the feature:
- `scope.files` and `scope.tests` if the feature has a `scope` field (added by /writ-spec)
- `title` and `description` for keyword-based fallback

## Step 3: Compute impact

### If the feature has `scope.files`

Use `scope.files` as the starting set of directly affected files.
Mark each as `(modify)` or `(create)` based on whether the file exists on disk.

### If no scope field

Search `profile.json` for files matching keywords from the feature `title` and
`description`. Check file paths and export names. Present results as "estimated"
rather than "scoped":
"Note: this feature has no scope field. Files below are estimated from keyword matching."

### Test lookup

For each directly affected source file, look up `test-map.json -> source_to_tests`
to find related test files. Combine with `scope.tests` (if exists). Deduplicate.

### Transitive impact (1 hop only)

For each directly affected file, find files that import it by reversing the
`dependency_graph` (find all files whose dependency list includes the affected file).

Filter the indirect list:
- Only show indirect files that have entries in `test-map.json -> source_to_tests`
  (i.e., files with tests that might break). Silent imports from untested files
  are not actionable.
- If the indirect list exceeds 10 files, collapse to a count:
  "N additional files import these (not shown - likely shared utilities). Run a full
  test suite to catch regressions."

## Step 4: Output

```
=== Impact Analysis: <feature-id> ===

<feature title>
Status: <pending|in_progress|completed>

Directly affected files:
  src/routes/activity.ts        (modify)
  src/utils/csv.ts              (create)

Indirectly affected (1 hop, tested files only):
  src/routes/index.ts           (imports activity.ts, has tests)

Tests to run:
  tests/routes/activity.test.ts (covers activity.ts)
  tests/utils/csv.test.ts       (covers csv.ts - to be created)

Summary: 2 files directly affected, 1 indirectly, 2 test files.

Note: scope is advisory. Actual impact may differ during implementation.
```

### Edge cases

| Case | Output |
|------|--------|
| Feature has no scope AND no keyword matches in profile | "Cannot determine impact for feature '<id>'. The feature has no scope field and no files match its description. Fix: run /writ-spec --amend <id> to add scope, or add a scope field manually to writ.json." |
| Feature has scope but all files are new (none exist yet) | Show all as `(create)`. Note: "All scoped files are new. No existing dependency or test data available." |
| Test-map has no entries for affected files | "No test mappings found for affected files. These files have no test coverage in the test map." |
| Profile is stale (generated_at > 24 hours ago) | Prepend warning: "Profile was generated at <timestamp> (>24h ago). Run /writ-profile to refresh for more accurate results." |

## Error handling

All errors must include: what happened, why, and how to fix.

| Condition | Message |
|-----------|---------|
| No feature ID argument | "No feature ID provided. Usage: /writ-diff <feature-id>. Why: /writ-diff analyzes impact for a specific feature. Fix: provide a feature ID from writ.json. Run /writ-status to see available features." |
| No profile.json | "No codebase profile found. Why: /writ-diff needs the dependency graph and test mappings to show impact analysis. Fix: run /writ-profile first." |
| No writ.json | "No writ.json found. Why: /writ-diff needs a feature spec to analyze. Fix: run /writ-spec or /writ-ingest first." |
| Feature not found | "Feature '<id>' not found in writ.json. Why: the ID must match a feature in the spec. Fix: check available features with /writ-status." |
