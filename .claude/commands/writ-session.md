---
description: Full Writ session orchestrator - regression check, feature selection, plan, implement, verify, commit
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent
---

Run a complete Writ development session. This is the primary entry point for all development work.

## Step 1: Load state

Read all three state sources in parallel:
- `writ.json` (full contents)
- `progress.json` (full contents)
- `git log --oneline -20` (recent history)

Check for leftover safety tags from previous sessions:
`git tag -l 'writ-pre-*'`
If any exist, note: "Found stale safety tag(s) from a previous session.
Clean up with `git tag -d <tag-name>`."

If `writ.json` does not exist, output:
```
No writ.json found. Run /writ-ingest <prd-file> to generate one first,
or use the writ-initializer agent if starting a brand new project.
```
Then stop.

Summarize current state:
```
Project: <name>
Features: <N> total, <X> completed, <Y> pending, <Z> in_progress
Last session: <date> - <feature_id> - <summary>
```

## Step 2: Regression check

Run `/writ-verify --all` before doing anything else.

If any previously-completed feature now fails verification:
```
REGRESSION DETECTED in: <feature-id>
Failing criterion: <description>
Command: <target>

Cannot start new work until regressions are resolved.

How would you like to proceed?
1. Fix the regression (I will investigate and propose a fix for your approval)
2. Skip and continue (risky)
```

**STOP HERE. Do not diagnose, do not run any commands, do not restore any files.**
Output the message above and wait for the user to reply with 1 or 2.
Only after receiving a reply should you take any action.

If all checks pass (or no features are completed yet), continue.

## Step 3: Select next feature

Find the next feature to implement using these rules in order:
1. Any feature with status `in_progress` (resume interrupted work first)
2. The highest-priority `pending` feature whose `depends_on` list is entirely `completed`
3. If multiple features tie on priority, take the one listed first in writ.json

If $ARGUMENTS contains a feature ID, use that feature instead (after validating it exists
and its dependencies are met).

If no eligible features exist:
```
All features complete! (or all remaining features are blocked by incomplete dependencies)
Blocked features: <list with their blocking dependencies>
```
Then stop.

Present the selected feature:
```
Selected: <feature-id> - <title> (priority <N>)
Description: <description>
Depends on: <list or "none">

Acceptance criteria:
  1. [<type>] <description>
  2. [<type>] <description>
  ...
```

## Step 4: Generate implementation plan

<investigate_before_answering>
Before proposing any implementation, run this reconnaissance:
1. Project shape: Glob for entry points (main/index/app/server) and
   list top-level source directories
2. Feature neighborhood: Glob and Grep for files related to this
   feature's domain (by name and by import/reference)
3. Shared utilities: Check lib/, utils/, helpers/, shared/, common/
   for reusable code you should call, not duplicate
4. Conventions: Read 1-2 existing files in the area you will change
   to match patterns (naming, error handling, module structure)
5. File manifest: List every file you will create or modify - read
   each one before proposing changes

Never propose changes to code you haven't read.
</investigate_before_answering>

Generate a concrete implementation plan:
```
Implementation plan for <feature-id>:

Files to create:
  - <path>: <purpose>

Files to modify:
  - <path>: <what changes and why>

Approach:
  <2-4 sentences describing the implementation strategy>

Criteria coverage (every criterion must be mapped):
  - Criterion 1: will pass after <specific change>
  - Criterion 2: already satisfied - <brief explanation>
  ...
```

If $ARGUMENTS contains `--auto`, skip this confirmation and proceed directly to Step 5.
Otherwise ask: "Does this plan look correct? Proceed with implementation?"
and wait for user confirmation before writing any code.

## Step 5: Execute

<anti_overengineering>
Implement only what is required to pass the acceptance criteria. Do not:
- Refactor code that works but could be "cleaner"
- Add error handling for cases not covered by acceptance criteria
- Create utility functions or abstractions for one-time use
- Add logging, metrics, or observability beyond what's specified
- Write tests beyond what the criteria require
- Add comments or documentation to code you did not change

The spec is the contract. Pass the criteria. Nothing more.
</anti_overengineering>

Create a safety tag before writing any code:
`git tag writ-pre-<feature-id>`

Update `writ.json` to set this feature's status to `"in_progress"` before coding.

Implement the feature according to the approved plan. Make targeted, minimal changes.

## Step 6: Verify

Run `/writ-verify <feature-id>` after implementation.

If all criteria pass: proceed to Step 7.

If some criteria fail:
- Diagnose the specific failure
- Make targeted fixes
- Re-run `/writ-verify <feature-id>`
- Repeat up to 3 times total

After 3 failed attempts, output:
```
Verification failed after 3 attempts.
Failing criteria:
  - <criterion>: <diagnosis>

Options:
1. Continue debugging (describe what you want to try)
2. Revert changes and revisit the spec
3. Mark as blocked and move to next feature
4. Revert to pre-session state
   (will run `git reset --hard writ-pre-<feature-id>` after your confirmation)
```
Wait for user guidance.

## Step 7: Commit

Run `/writ-commit <feature-id>` to create the structured commit and update state files.

Clean up safety tag: `git tag -d writ-pre-<feature-id> 2>/dev/null`

## Step 8: Suggest next session

After successful commit, output:
```
Session complete!

Completed: <feature-id> - <title>
Commit: <hash>

Remaining: <N> features pending

Next recommended: <next-feature-id> - <title>
  Run /writ-session to continue.
```
