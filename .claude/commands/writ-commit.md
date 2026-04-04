---
description: Create atomic commit for a verified feature and update progress.json (writ-commit)
allowed-tools: Read, Bash, Write, Edit
---

Create a structured git commit for the feature ID in $ARGUMENTS, then update state files.

## Pre-flight check

1. Read `writ.json` and find the feature matching $ARGUMENTS. If not found, output
   "ERROR: Feature '<id>' not found in writ.json" and stop.

2. Read `progress.json`. Check whether verification has been run for this feature
   in the current session. If the feature has no passing criteria recorded, warn:
   "WARNING: No verification results found for this feature. Run /writ-verify first."
   Ask user to confirm before proceeding.

3. Count how many acceptance criteria passed in the most recent verify run.

## Update state files

4. Update `progress.json` to record the completed feature. Add or update the entry
   for this feature ID:
   ```json
   {
     "status": "completed",
     "started_at": "<iso timestamp from when it was started, if known>",
     "completed_at": "<current iso timestamp>",
     "commit_hash": "TBD",
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

5. **REQUIRED** - Update `writ.json`: find the feature with matching `id` and set its
   `status` field to `"completed"`. This must be done even if the feature was previously
   marked `in_progress`. Only modify the `status` field, leave all other fields unchanged.
   Verify with: `python3 -c "import json; s=json.load(open('writ.json')); print([f['status'] for f in s['features'] if f['id']=='<feature-id>'])"` - must show `['completed']`.

6. If `progress.md` exists, append a one-line entry:
   ```
   - [<date>] <feature-id>: <title> - commit <short-hash>
   ```

## Commit

7. Stage all modified and new files:
   ```
   git add -A
   ```
   But first review `git status` - do not stage files that look unrelated to the feature
   (e.g., .env files, large binaries, unrelated config changes). List what you are staging.

8. Create a single commit that includes both the implementation and state file updates:
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

9. Capture the commit hash and backfill it into `progress.json`:
   ```bash
   HASH=$(git rev-parse HEAD)
   ```
   Update the `commit_hash` field for this feature in `progress.json` with $HASH.
   Also update `progress.md` if the "commit TBD" placeholder exists.

   Then amend the commit to include this update:
   ```bash
   git add progress.json progress.md
   git commit --amend --no-edit
   ```

   This is safe because the commit was just created locally and has not been pushed.
   Note: the stored hash is the pre-amend hash. It differs from the final HEAD by
   one amend step (the hash backfill itself). This is acceptable since the hash is
   informational, not used for git operations.

10. Output confirmation:
    ```
    Committed: <feature-id>
    Hash: <full commit hash>
    Next: <next recommended feature, or "All features complete!">
    ```
