---
description: Evaluate acceptance criteria for a feature or all features
allowed-tools: Read, Glob, Grep, Bash
---

Evaluate acceptance criteria from `spec.json` for the feature(s) specified in $ARGUMENTS.

- If $ARGUMENTS is a feature ID: evaluate that feature only.
- If $ARGUMENTS is `--all`: evaluate all features whose status is not `pending`.

## Instructions

1. Read `spec.json`. If it does not exist, output "ERROR: spec.json not found" and stop.

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
`<command> > /tmp/sdd-verify-output.txt 2>&1; echo $?`

4. For each feature, output a structured result:

```
Feature: <feature-id> - <title>
Status: PASS (N/N) | PARTIAL (N/M) | FAIL (0/N)

  [PASS] <criterion description>
  [FAIL] <criterion description>
  ...
```

5. After all features, output an overall summary:

```
=== Verification Summary ===
PASSED: N features
FAILED: M features
BLOCKED: list feature IDs that failed
```

6. If --all was specified and any feature fails, output:
```
REGRESSION DETECTED: Do not start new features until failures are resolved.
```

## Rules

- Do not modify any files during verification.
- Do not interpret or guess at criterion intent - evaluate mechanically.
- If a command times out or produces an error, mark the criterion FAIL and note the error.
- Exit codes are authoritative: 0 = success, non-zero = failure.
