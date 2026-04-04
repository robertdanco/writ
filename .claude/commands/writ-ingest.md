---
description: Two-phase PRD ingestion - parse a PRD into writ.json then expand acceptance criteria
allowed-tools: Read, Glob, Grep, Bash, Write, WebFetch
---

Convert the PRD at $ARGUMENTS into a structured `writ.json`. $ARGUMENTS is a file path or URL.

## Phase 1: Parse

1. Load the PRD:
   - If $ARGUMENTS is a URL: use WebFetch to retrieve it.
   - If $ARGUMENTS is a file path: use Read to load it.
   - If $ARGUMENTS is empty: check for a PRD or requirements file in the current directory
     (look for `prd.md`, `requirements.md`, `REQUIREMENTS.md`, `PRD.md`). If none found,
     ask the user to provide a file path or URL.

2. Read the PRD carefully. Extract:
   - Project name and description
   - All features, user stories, and functional requirements
   - Any explicit constraints, non-goals, or out-of-scope items

3. Check if `writ.json` already exists. If it does, read it and ask:
   "writ.json already exists with N features. Merge new features into it, or replace it?"
   Wait for user response before proceeding.

4. Decompose the PRD into features at the right granularity:
   - Each feature = one user-observable behavior ("a user can do X and see Y")
   - Each feature should be completable in one session (one context window)
   - If a requirement would take multiple sessions to implement, split it
   - Aim for features that have 3-7 verifiable acceptance criteria
   - Flag any feature that would touch 8+ files or need 7+ criteria with
     `[SPLIT?]` - these are likely two features sharing an ID

5. Generate a draft `writ.json` using the schema below. Use kebab-case for feature IDs.
   Order features by logical dependency (dependencies come first). Assign priorities:
   1 = core/foundational, 5 = polish/optional. Mark all status as `"pending"`.

   Schema:
   ```json
   {
     "project": "<project name>",
     "version": "1.0.0",
     "created_at": "<ISO timestamp>",
     "description": "<one sentence project description>",
     "features": [
       {
         "id": "<kebab-case-id>",
         "title": "<short human-readable title>",
         "description": "<what the user can do, from user perspective>",
         "depends_on": ["<feature-id>", ...],
         "priority": <1-5>,
         "status": "pending",
         "acceptance_criteria": []
       }
     ]
   }
   ```

6. Present the draft feature list to the user:
   ```
   Parsed N features from PRD:

   Priority 1:
     - <id>: <title> [depends on: ...]
   Priority 2:
     - <id>: <title>
   ...

   Does this decomposition look correct? Any features to add, remove, or split?
   ```
   Wait for user feedback. Revise if requested.

## Phase 2: Expand acceptance criteria

**Step 6.5: Establish verification context**

Before writing criteria, determine how the project is invoked:
- Read `CLAUDE.md` for build/test/start commands. If found, use those.
- If no CLAUDE.md and no existing code (greenfield project), ask the user:
  "How will this project be invoked once built? Examples:
  - `node server.js` (HTTP server on port 3000)
  - `python main.py --input file.csv` (CLI tool)
  - `import { lib } from './src'` (library, verified via test runner)
  This determines how acceptance criteria will verify features."
  Wait for the response.

Use the invocation pattern to anchor `command_succeeds` criteria for all features.
For servers, use this lifecycle pattern:
`bash -c "<start> & sleep 2 && <check> ; kill %1"`

**Step 6.75: Confirm behavioral scenarios (always required)**

Regardless of whether CLAUDE.md exists or code is present, always do this step.
Do NOT skip it or proceed directly to criteria generation.

For each approved feature, propose a concrete "when I do X, I expect Y" scenario
based on the PRD. Use specific values, endpoints, inputs, and outputs. Where the
PRD is ambiguous, mark gaps with `[NEEDS CLARIFICATION]` and ask a targeted question.

Present to the user:
```
Before generating criteria, confirm what "working" looks like for each feature.
I've proposed scenarios from the PRD - correct anything wrong and fill in gaps:

1. <feature-id>: <concrete scenario with specific inputs and expected outputs>
   [NEEDS CLARIFICATION: <targeted question about a gap, if any>]

2. <feature-id>: <concrete scenario>
   [NEEDS CLARIFICATION: <question>]
...
```

Wait for user feedback. Revise scenarios based on their answers.
All `[NEEDS CLARIFICATION]` markers must be resolved before proceeding to
criteria generation. Do not guess - ask.

These confirmed
scenarios become the behavioral foundation for criteria generation - each scenario
maps directly to one or more `command_succeeds` criteria.

7. For each feature, generate concrete acceptance criteria. Use the confirmed
   behavioral scenarios from step 6.75 as the basis for `command_succeeds` criteria.

   Study these examples to calibrate quality:

   **Example A - CLI tool feature: "user can add a task by name"**
   ```json
   [
     {"type": "file_exists", "target": "cli.js", "expected": ""},
     {"type": "command_succeeds", "target": "node cli.js add \"Buy milk\" && node cli.js list | grep -q \"Buy milk\"", "expected": ""},
     {"type": "command_succeeds", "target": "node cli.js add \"\" 2>&1 | grep -qi \"error\\|usage\"", "expected": ""}
   ]
   ```
   The behavioral criteria invoke the CLI, trigger the feature, and check the
   result. The file_exists is supporting context.

   **Example B - HTTP server feature: "user can create an account"**
   ```json
   [
     {"type": "file_exists", "target": "src/routes/register.js", "expected": ""},
     {"type": "command_succeeds", "target": "bash -c 'node server.js & sleep 2 && curl -sf -X POST -H \"Content-Type: application/json\" -d \"{\\\"email\\\":\\\"test@test.com\\\",\\\"pass\\\":\\\"secret\\\"}\" http://localhost:3000/register | grep -q email ; kill %1'", "expected": ""},
     {"type": "command_succeeds", "target": "bash -c 'node server.js & sleep 2 && curl -sf http://localhost:3000/register -o /dev/null -w \"%{http_code}\" | grep -q 405 ; kill %1'", "expected": ""}
   ]
   ```
   Each behavioral criterion manages the server lifecycle and checks a specific
   response, not just that the server starts.

   **Example C** - Config-driven feature:
   Feature: "User can customize the dashboard layout via config file"
   ```json
   [
     {"type": "file_exists", "target": "config/dashboard.json", "expected": ""},
     {"type": "json_path_check", "target": "config/dashboard.json", "expected": ".layout"},
     {"type": "file_contains", "target": "src/dashboard.ts", "expected": "loadConfig"},
     {"type": "command_succeeds", "target": "node src/cli.js dashboard --config config/dashboard.json | grep -q 'Layout loaded'", "expected": ""}
   ]
   ```
   Config and data features benefit from `json_path_check` and `file_contains`
   to verify structure without running the full application.

   **Criterion types (reference):**
   - `command_succeeds` - run a command, check exit code. Best for: runtime behavior,
     CLI output, API responses, end-to-end flows.
   - `test_passes` - run a test command. Best for: projects with existing test suites.
   - `file_exists` - check a file was created. Best for: scaffolding, code generation,
     build output.
   - `file_contains` - check for specific content in a file. Best for: config files,
     generated output, template rendering.
   - `json_path_check` - check a JSON field via jq filter. Best for: API responses,
     config validation, structured output.
   - `grep_match` - pattern search across files. Best for: code conventions, import
     patterns, cross-file consistency.

   **Rules:**
   - Every feature SHOULD have at least one behavioral criterion (`command_succeeds` or
     `test_passes`) that exercises the feature's runtime behavior. Exceptions: pure
     config or data features where `json_path_check` or `file_contains` fully verifies
     the behavior.
   - If the project has a linter or formatter configured (eslint, prettier,
     ruff, clippy, etc.), include a `command_succeeds` criterion running the
     lint command on every feature that creates or modifies source files.
   - Syntax checks (`--check`), build checks (`npm run build`), and help flags do NOT
     count as behavioral - they verify structure, not behavior
   - Be specific: multi-word expected strings, exact file paths, concrete values
   - 3-7 criteria per feature

8. Present the expanded criteria for user review. For each feature, include a
   discrimination check:
   ```
   Feature: <id> - <title>
   Criteria:
     1. [command_succeeds] <target>: <description>
     2. [file_exists] <target>: <description>
     ...
   Discrimination: <why at least one criterion would FAIL without this feature>
   ```
   Show all features. Ask: "Any criteria to adjust before writing writ.json?"

9. After approval, write the complete `writ.json` to the project root.

10. If `progress.json` does not exist, create it from the template:
    ```json
    {
      "last_session": {
        "date": "",
        "feature_id": "",
        "summary": "writ.json created via /writ-ingest",
        "next_recommended": "<id of first priority-1 feature>"
      }
    }
    ```

11. Output:
    ```
    writ.json written: N features, M total acceptance criteria
    Next: Run /writ-session to begin implementation
    ```
