---
description: Evaluate acceptance criteria for a feature or all features. Supports --all (regression check), --pending (discriminative check), or a feature ID. Enhanced with selective test execution, criterion timeouts, replay logging, and smart criterion suggestions.
allowed-tools: Read, Glob, Grep, Bash, Write, Agent
---

Evaluate acceptance criteria from `writ.json` for the feature(s) specified in $ARGUMENTS.

$ARGUMENTS must be one of:
- A feature ID: evaluate that feature only (normal pass/fail).
- `--all`: evaluate all features whose status is not `pending` (regression check).
- `--pending`: **discriminative check** - evaluate all pending features. Invert pass/fail
  semantics: a criterion that PASSES is flagged as WEAK (it passes on unimplemented code).
  A criterion that FAILS is correct. Do NOT run this as a normal evaluation.
- empty: same as `--all`.

Optional flags (can combine with any mode above):
- `--auto`: suppress interactive suggestion prompts (log suggestions silently).
- `--no-suggestions`: skip the smart criterion suggestion subagent entirely.

**IMPORTANT**: `--pending` uses inverted semantics. Do not evaluate pending features using
normal pass/fail. See step 4 for the required output format.

## Instructions

### Step 1: Load spec and configuration

Read `writ.json`. If it does not exist: "ERROR: writ.json not found. Why: writ-verify needs
a spec to evaluate. Fix: run /writ-ingest or /writ-spec first." Stop.

If `writ.json` has a top-level `defaults` object with a `criterion_timeout` field (integer,
seconds), note it as the project-level timeout default.

### Step 1b: Detect timeout command

Run:
```bash
if command -v gtimeout >/dev/null 2>&1; then echo "gtimeout"
elif command -v timeout >/dev/null 2>&1; then echo "timeout"
else echo "none"
fi
```

- If `gtimeout`: use `gtimeout` for timeout wrapping.
- If `timeout`: use `timeout` for timeout wrapping.
- If `none`: warn once: "WARNING: Neither `timeout` nor `gtimeout` found. Why: criterion
  timeout enforcement requires GNU coreutils. Fix: `brew install coreutils` (macOS) or
  `apt install coreutils` (Linux)." Continue without timeout enforcement.

### Step 1c: Load test-map (selective execution)

If `.writ/test-map.json` exists, read it and store the `source_to_tests` mapping for use
in step 3. If it does not exist, selective test execution is disabled (no warning needed).

Selective execution only applies to **single-feature verification** (not `--all` or `--pending`).
Regression checks must run the full test suite - there is no single feature diff to scope against.

### Step 2: Identify features

Identify which features to evaluate based on $ARGUMENTS.

### Step 3: Evaluate criteria

For each feature, evaluate every acceptance criterion mechanically. For each criterion,
follow this three-phase process:

#### Phase A: Execute with timeout

**For `command_succeeds` and `test_passes` types only** (these run user-specified shell commands
that could hang), wrap the command in a timeout:

```
<timeout_cmd> <N> <original command> > /tmp/writ-verify-<feature-id>-stdout.txt 2> /tmp/writ-verify-<feature-id>-stderr.txt
```

Timeout value resolution (first match wins):
1. Per-criterion `timeout` field (integer seconds) if present in the criterion object
2. `defaults.criterion_timeout` from writ.json (if present)
3. 60 seconds (hardcoded default)

If the command exits with code 124 (timeout signal), mark the criterion FAIL with message:
"Timed out after Ns".

**For all other types** (`file_exists`, `file_contains`, `grep_match`, `json_path_check`),
evaluate using the standard methods below without timeout wrapping. These run known commands
(`test -f`, `grep`, `jq`) that will not hang. Still redirect output for replay capture:

```
<command> > /tmp/writ-verify-<feature-id>-stdout.txt 2> /tmp/writ-verify-<feature-id>-stderr.txt
```

Standard evaluation methods:

| Criterion type | Verification method |
|---|---|
| `file_exists` | `test -f <target> && echo PASS || echo FAIL` |
| `file_contains` | `grep -qF "<expected>" "<target>" && echo PASS || echo FAIL` |
| `command_succeeds` | Run `<target>`, check exit code 0 = PASS |
| `test_passes` | Run `<target>` as a shell command, check exit code 0 = PASS |
| `grep_match` | `grep -r "<expected>" <target> > /dev/null 2>&1 && echo PASS || echo FAIL` |
| `json_path_check` | `jq -e '<expected>' '<target>' > /dev/null 2>&1 && echo PASS || echo FAIL` |

For `json_path_check`, `target` is a JSON file path and `expected` is a jq filter expression
that must return truthy. If `jq` is not available, fall back to:
`python3 -c "import json,sys; d=json.load(open('<target>')); <python expression using d>"`.

#### Phase B: Selective test execution (test_passes only)

This phase applies ONLY when ALL of:
- The criterion type is `test_passes`
- `.writ/test-map.json` was loaded in Step 1c
- Mode is single-feature verification (NOT `--all` or `--pending`)

Process:
1. Get changed files: `git diff --name-only <base>` where `<base>` is:
   - `writ-pre-<feature-id>` tag (if it exists, from writ-session safety tag)
   - Otherwise `HEAD~1`
   - If neither works (fresh repo), use `git diff --name-only HEAD` for uncommitted changes
2. For each changed file, look up `source_to_tests[<file>]` from the test-map.
3. Collect all test files that cover any changed source file.
4. If relevant test files found: attempt to run only those tests instead of the full command.
   - For common test runners, modify the command:
     - `npm test` or `npx jest` -> append `-- <test files>`
     - `pytest` -> append `<test files>`
     - `go test ./...` -> replace `./...` with specific packages
   - If the test runner is not recognized, run the original command as-is.
5. **Safety net**: If selective tests FAIL, also run the full original command to confirm
   the failure. A stale test-map must never hide regressions. If the full suite passes
   but selective failed, warn: "Selective test failed but full suite passed. Test-map may
   be stale. Run /writ-profile to regenerate."
6. If no changed files map to any tests, run the original command as-is.

#### Phase C: Record result

After each criterion completes, record:
- `description`: criterion description
- `type`: criterion type
- `target`: criterion target
- `expected`: criterion expected value
- `exit_code`: the command's exit code
- `pass`: true if PASS, false if FAIL
- `duration_s`: wall-clock seconds for this criterion (integer). Capture with:
  `START=$(date +%s); <command>; DURATION=$(( $(date +%s) - START ))`
  (`date +%s` works on both macOS and Linux, unlike `%N` which is GNU-only)
- `stdout_tail`: last 50 lines of stdout (read from /tmp/writ-verify-<feature-id>-stdout.txt)
- `stderr_tail`: last 50 lines of stderr (read from /tmp/writ-verify-<feature-id>-stderr.txt)
- `timeout_applied`: timeout value used (integer seconds, or null if no timeout)
- `timed_out`: true if exit code was 124 from timeout
- `selective_test`: true if selective execution was used for this criterion

**CRITICAL**: Never dump full test output into the response. Run commands, capture exit codes,
and report summaries only.

### Step 3d: Write replay log

After evaluating ALL criteria for a feature, write the run log to:
`.writ/runs/<feature-id>/<ISO-timestamp>-<4-random-hex>.json`

The random hex suffix prevents filename collisions if verify runs twice in the same second.
Generate it with: `python3 -c "import random; print(format(random.randint(0,65535),'04x'))"`

Create the directory if needed: `mkdir -p .writ/runs/<feature-id>`

File contents:
```json
{
  "feature_id": "<id>",
  "timestamp": "<ISO timestamp>",
  "mode": "normal|pending|regression",
  "results": [
    {
      "description": "...",
      "type": "...",
      "target": "...",
      "expected": "...",
      "exit_code": 0,
      "pass": true,
      "duration_s": 12,
      "stdout_tail": "...",
      "stderr_tail": "...",
      "timeout_applied": 60,
      "timed_out": false,
      "selective_test": false
    }
  ],
  "summary": {
    "total": 5,
    "passed": 4,
    "failed": 1
  }
}
```

If directory creation fails: "WARNING: Could not create .writ/runs/<id>/. Why: directory
creation failed. Fix: check filesystem permissions." Continue without writing the log.

### Step 3e: Cleanup generated files

After writing the replay log for each feature, clean up any files modified during evaluation.

**Skip cleanup if any of:**
- `--pending` mode (user may have uncommitted work in progress)
- `git status --porcelain` shows uncommitted changes to tracked files (user is mid-edit)

If skipping due to uncommitted changes, warn once:
"Skipping cleanup: uncommitted changes detected. Build artifacts from verification may remain."

Otherwise, run:

```bash
git checkout -- . 2>/dev/null || true
```

This restores files that criterion evaluation may have modified (coverage reports, build
artifacts, compiled output). The `|| true` ensures it does not fail on a clean working tree.

Also clean up temp files:
```bash
rm -f /tmp/writ-verify-<feature-id>-stdout.txt /tmp/writ-verify-<feature-id>-stderr.txt
```

**Known limitation**: cleanup runs once after all criteria for a feature, not between each
criterion. If an earlier criterion generates artifacts that cause a later criterion to produce
a false positive, the ordering matters. This is a pragmatic tradeoff - inter-criterion cleanup
is expensive and rarely needed.

### Step 4: Output results

For each feature, output a structured result.

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
  [WEAK - passes]  <criterion description>  <- passes on empty codebase, criterion is too weak
  ...
```

### Step 5: Overall summary

**Normal mode:**
```
=== Verification Summary ===
PASSED: N features
FAILED: M features
BLOCKED: list feature IDs that failed
Replay logs: .writ/runs/<feature-id>/<timestamp>-<hex>.json
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

### Step 6: Regression warning

If `--all` was specified and any feature fails:
```
REGRESSION DETECTED: Do not start new features until failures are resolved.
```

### Step 7: Smart criterion suggestions

**Skip this step entirely if any of:**
- `$ARGUMENTS` contains `--no-suggestions`
- Mode is `--all` (regression checks verify existing features, not candidates for new criteria)
- Mode is `--pending` (discriminative checks don't need suggestions)
- Any criterion for this feature FAILED (suggestions are for strengthening passing features)

**Process:**

1. Capture the git diff for context. Run:
   ```bash
   git diff writ-pre-<feature-id> 2>/dev/null || git diff HEAD~1 2>/dev/null || git diff HEAD 2>/dev/null || echo "No diff available"
   ```
   Store the output (truncate to first 500 lines if very large).

2. Read the feature's spec and criteria from writ.json.

3. Use the Agent tool to spawn a read-only suggestion subagent with this prompt:

   > You are a verification criteria reviewer. Given a feature spec and its implementation
   > diff, propose 0-3 additional acceptance criteria that would strengthen verification.
   >
   > Feature: <feature title and description from writ.json>
   >
   > Existing criteria:
   > <list all current criteria with type/target/expected>
   >
   > Implementation diff:
   > <the git diff captured above>
   >
   > Rules:
   > - Only propose criteria that test behavior NOT already covered by existing criteria.
   > - Each criterion must use one of the 6 types: file_exists, file_contains,
   >   command_succeeds, test_passes, grep_match, json_path_check.
   > - Each criterion must be mechanically verifiable (exit code, not judgment).
   > - Propose 0 criteria if existing coverage is sufficient. Do not pad.
   > - Return ONLY valid JSON in this exact format, no other text:
   >   ```json
   >   [
   >     {
   >       "description": "...",
   >       "type": "...",
   >       "target": "...",
   >       "expected": "...",
   >       "rationale": "why this criterion adds value"
   >     }
   >   ]
   >   ```

   The subagent must have allowed-tools: Read, Glob, Grep only (NO Bash, NO Write).

4. Parse the subagent's response as JSON. If parsing fails, warn: "WARNING: Smart suggestion
   subagent returned unparseable response. Why: subagent output was not valid JSON. Fix:
   suggestions are optional - verification results are unaffected." Skip to cleanup.

5. If the subagent returned an empty array (`[]`), output: "No additional criteria suggested."

6. Write suggestions to `.writ/runs/<feature-id>/suggestions.json`:
   ```json
   {
     "feature_id": "<id>",
     "timestamp": "<ISO timestamp>",
     "suggestions": [
       {
         "description": "...",
         "type": "...",
         "target": "...",
         "expected": "...",
         "rationale": "..."
       }
     ]
   }
   ```

7. Present suggestions to the user:
   - If `$ARGUMENTS` contains `--auto`: log silently:
     "AUTO: <N> criterion suggestions written to .writ/runs/<feature-id>/suggestions.json"
   - Otherwise (interactive): present each suggestion with its rationale and ask:
     ```
     Suggested criterion: <description>
     Type: <type> | Target: <target>
     Rationale: <rationale>
     Accept this suggestion? (y/n)
     ```
     Accepted suggestions are noted. Tell the user: "Run `/writ-spec --amend <feature-id>`
     to review and apply accepted suggestions to writ.json."

8. If the Agent tool call fails for any reason: "WARNING: Smart suggestion subagent failed.
   Why: <error message>. Fix: suggestions are optional - verification results are unaffected."
   Continue normally.

## Rules

- Do not modify source files during verification. Writing to `.writ/runs/` is permitted.
- Do not interpret or guess at criterion intent - evaluate mechanically.
- Exit codes are authoritative: 0 = success, non-zero = failure.
- If a command times out (exit 124), mark the criterion FAIL with "Timed out after Ns".
- If timeout tooling is unavailable, warn once and run commands without timeout.
- Clean up generated files after evaluating each feature unless uncommitted changes are detected.
- Clean up temp files (`/tmp/writ-verify-<feature-id>-*`) after each feature.
- Cleanup runs once after all criteria per feature, not between criteria. Criteria ordering
  could theoretically cause false positives from stale artifacts, but this is rare in practice.
- Selective test execution is disabled in `--all` and `--pending` modes.
- Smart suggestions only run for single-feature verification when all criteria pass and
  `--no-suggestions` is not set. Skipped in `--all` and `--pending` modes.
