---
description: Create atomic commit for a verified feature and update progress.json
allowed-tools: Read, Bash, Write, Edit
---

Create a structured git commit for the feature ID in $ARGUMENTS, then update state files.

## Pre-flight check

1. Read `spec.json` and find the feature matching $ARGUMENTS. If not found, output
   "ERROR: Feature '<id>' not found in spec.json" and stop.

2. Read `progress.json`. Check whether verification has been run for this feature
   in the current session. If the feature has no passing criteria recorded, warn:
   "WARNING: No verification results found for this feature. Run /sdd-verify first."
   Ask user to confirm before proceeding.

3. Count how many acceptance criteria passed in the most recent verify run.

## Commit

4. Stage all modified and new files:
   ```
   git add -A
   ```
   But first review `git status` - do not stage files that look unrelated to the feature
   (e.g., .env files, large binaries, unrelated config changes). List what you are staging.

5. Create the commit with this exact message format:
   ```
   feat(<feature-id>): <short description derived from feature title>

   Spec: <feature title>
   Criteria: <N>/<M> passed
   ```

   Use a HEREDOC to pass the commit message:
   ```bash
   git commit -m "$(cat <<'EOF'
   feat(<feature-id>): <description>

   Spec: <feature title>
   Criteria: N/M passed
   EOF
   )"
   ```

6. Capture the resulting commit hash: `git rev-parse HEAD`

## Update state files

7. Update `progress.json` to record the completed feature. Add or update the entry
   for this feature ID:
   ```json
   {
     "status": "completed",
     "started_at": "<iso timestamp from when it was started, if known>",
     "completed_at": "<current iso timestamp>",
     "commit_hash": "<hash from step 6>",
     "sessions": <increment by 1>,
     "criteria_results": {
       "<criterion description>": true/false,
       ...
     }
   }
   ```
   Also update `last_session` at the root:
   ```json
   "last_session": {
     "date": "<current iso timestamp>",
     "feature_id": "<feature-id>",
     "summary": "<one sentence summary of what was implemented>",
     "next_recommended": "<id of next pending feature, or empty if none>"
   }
   ```

8. Update `spec.json`: set `features[*].status` to `"completed"` for this feature ID.
   Only modify the `status` field.

9. If `progress.md` exists, append a one-line entry:
   ```
   - [<date>] <feature-id>: <title> - commit <short-hash>
   ```

10. Create a second commit for the state file updates:
    ```
    chore(sdd): mark <feature-id> complete in progress.json
    ```

11. Output confirmation:
    ```
    Committed: <feature-id>
    Hash: <full commit hash>
    Next: <next recommended feature, or "All features complete!">
    ```
