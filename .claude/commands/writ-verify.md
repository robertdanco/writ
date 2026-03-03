---
description: Evaluate acceptance criteria for a feature or all features. Supports --all (regression check), --pending (discriminative check), or a feature ID.
allowed-tools: Read, Glob, Grep, Bash
---

Evaluate acceptance criteria from `writ.json` for the feature(s) specified in $ARGUMENTS.

$ARGUMENTS must be one of:
- A feature ID: evaluate that feature only (normal pass/fail).
- `--all`: evaluate all features whose status is not `pending` (regression check).
- `--pending`: **discriminative check** - evaluate all pending features. Invert pass/fail
  semantics: a criterion that PASSES is flagged as WEAK (it passes on unimplemented code).
  A criterion that FAILS is correct. Do NOT run this as a normal evaluation.
- empty: same as `--all`.

**IMPORTANT**: `--pending` uses inverted semantics. Do not evaluate pending features using
normal pass/fail. See step 4 for the required output format.

## Instructions

1. Read `writ.json`. If it does not exist, output "ERROR: writ.json not found" and stop.

2. Identify which features to evaluate based on $ARGUMENTS.

3. For each feature, evaluate every acceptance criterion mechanically:

| Criterion type | Verification method |
|---|---|
| `file_exists` | `test -f <target> && echo PASS || echo FAIL` |
| `file_contains` | `grep -qF "<expected>" "<target>" && echo PASS || echo FAIL` |
| `command_succeeds` | Run `<target>`, check exit code 0 = PASS |
| `test_passes` | Run `<target>` as a shell command, check exit code 0 = PASS |
| `grep_match` | `grep -r "<expected>" <target> > /dev/null 2>&1 && echo PASS || echo FAIL` |
| `json_path_check` | `jq -e '<expected>' '<target>' > /dev/null 2>&1 && echo PASS || echo FAIL` |

For `json_path_check`, `target` is a JSON file path and `expected` is a jq filter expression
that must return truthy (e.g., `.version == "1.0.0"`, `.dependencies.react != null`,
`.users | length > 0`). If `jq` is not available, fall back to:
`python3 -c "import json,sys; d=json.load(open('<target>')); <python expression using d>"`.

**CRITICAL**: Never dump full test output into the response. Run commands, capture exit codes,
and report summaries only. If you must log output, write to a temp file:
`<command> > /tmp/writ-verify-output.txt 2>&1; echo $?`

4. For each feature, output a structured result.

   **Normal mode** (`--all` or feature ID):
   ```
   Feature: <feature-id> - <title>
   Status: PASS (N/N) | PARTIAL (N/M) | FAIL (0/N)

     [PASS] <criterion description>
     [FAIL] <criterion description>
     ...
   ```

   **`--pending` mode** (discriminative check):
   ```
   Feature: <feature-id> - <title>
     [OK - fails]     <criterion description>
     [WEAK - passes]  <criterion description>  ← passes on empty codebase, criterion is too weak
     ...
   ```

5. After all features, output an overall summary.

   **Normal mode:**
   ```
   === Verification Summary ===
   PASSED: N features
   FAILED: M features
   BLOCKED: list feature IDs that failed
   ```

   **`--pending` mode:**
   ```
   === Discriminative Check Summary ===
   Features checked: N
   Weak criteria found: M
   <If M > 0:>
   WEAK CRITERIA (pass on empty codebase - strengthen before implementing):
     <feature-id> #<n>: <criterion description>
     ...
   <If M == 0:>
   All criteria correctly fail on empty codebase. Criteria are discriminative.
   ```

6. If `--all` was specified and any feature fails, output:
   ```
   REGRESSION DETECTED: Do not start new features until failures are resolved.
   ```

## Rules

- Do not modify any files during verification.
- Do not interpret or guess at criterion intent - evaluate mechanically.
- If a command times out or produces an error, mark the criterion FAIL and note the error.
- Exit codes are authoritative: 0 = success, non-zero = failure.
