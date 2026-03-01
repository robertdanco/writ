---
description: Two-phase PRD ingestion - parse a PRD into spec.json then expand acceptance criteria
allowed-tools: Read, Glob, Grep, Bash, Write, WebFetch
---

Convert the PRD at $ARGUMENTS into a structured `spec.json`. $ARGUMENTS is a file path or URL.

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

3. Check if `spec.json` already exists. If it does, read it and ask:
   "spec.json already exists with N features. Merge new features into it, or replace it?"
   Wait for user response before proceeding.

4. Decompose the PRD into features at the right granularity:
   - Each feature = one user-observable behavior ("a user can do X and see Y")
   - Each feature should be completable in one session (one context window)
   - If a requirement would take multiple sessions to implement, split it
   - Aim for features that have 3-7 verifiable acceptance criteria

5. Generate a draft `spec.json` using the schema below. Use kebab-case for feature IDs.
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

7. For each feature in the approved list, generate concrete, mechanically-verifiable
   acceptance criteria. Every criterion must have an unambiguous pass/fail result.

   Use these criterion types:

   | Type | When to use | Target | Expected |
   |---|---|---|---|
   | `file_exists` | A file must be created | File path | "" (empty) |
   | `file_contains` | A file must contain specific content | File path | String to find |
   | `command_succeeds` | A command must exit 0 | Shell command | "" (empty) |
   | `test_passes` | A test suite or specific test must pass | Test command | "" (empty) |
   | `grep_match` | A pattern must appear in files | Directory or glob | Pattern to match |
   | `json_path_check` | A JSON file field must have a specific value | JSON file path | jq filter expression (e.g., `.version == "2.0.0"`) |

   Rules for criteria:
   - Be specific about file paths and content - no vague criteria
   - If a requirement is subjective ("looks good", "is fast"), decompose into objective checks
   - Each criterion description must be self-explanatory to a developer unfamiliar with the project
   - 3-7 criteria per feature is the target range

8. Present the expanded criteria for user review:
   ```
   Feature: <id> - <title>
   Criteria:
     1. [file_exists] <target>: <description>
     2. [file_contains] <target> contains '<expected>': <description>
     3. [test_passes] <command>: <description>
   ```
   Show all features. Ask: "Any criteria to adjust before writing spec.json?"

9. After approval, write the complete `spec.json` to the project root.

10. If `progress.json` does not exist, create it from the template:
    ```json
    {
      "last_session": {
        "date": "",
        "feature_id": "",
        "summary": "spec.json created via /sdd-ingest",
        "next_recommended": "<id of first priority-1 feature>"
      }
    }
    ```

11. Output:
    ```
    spec.json written: N features, M total acceptance criteria
    Next: Run /sdd-session to begin implementation
    ```
