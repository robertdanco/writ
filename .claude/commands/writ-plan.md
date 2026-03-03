---
description: Generate implementation plan for next feature without executing - review before committing to a session
allowed-tools: Read, Glob, Grep, Bash
---

Generate a concrete implementation plan for the next feature without writing any code.
Use this to preview what /writ-session would do, check feasibility, or review approach
before committing to a full session.

## Step 1: Load state

Read `writ.json` + `progress.json` + `git log --oneline -10`.

If `writ.json` does not exist, output:
"No writ.json found. Run /writ-ingest first." and stop.

## Step 2: Select feature

Use the same selection logic as /writ-session:
1. Any feature with status `in_progress` (would resume this first)
2. Highest-priority `pending` feature whose `depends_on` are all `completed`
3. If multiple tie on priority, first in writ.json order

If $ARGUMENTS contains a feature ID, plan for that feature instead (validate it exists
and its dependencies are met first).

If no eligible feature exists, output:
```
No eligible features found.
(All remaining features are blocked, or all are complete.)
```
Then stop.

## Step 3: Regression check

For each completed feature, spot-check one criterion. If any fail, note:
```
NOTE: Regression detected in <feature-id> before planning.
A full session would need to address this before implementing new features.
```
Continue with the plan regardless (this is planning mode, not execution).

## Step 4: Explore codebase

<investigate_before_answering>
Before proposing anything, run this reconnaissance:
1. Project shape: Glob for entry points (main/index/app/server) and
   list top-level source directories
2. Feature neighborhood: Glob and Grep for files related to this
   feature's domain (by name and by import/reference)
3. Shared utilities: Check lib/, utils/, helpers/, shared/, common/
   for reusable code that would be called, not duplicated
4. Conventions: Read 1-2 existing files in the area to match patterns
   (naming, error handling, module structure)
5. File manifest: List every file to create or modify - read each one

Never propose changes to code you haven't read.
</investigate_before_answering>

## Step 5: Generate plan

Output a complete implementation plan:

```
Plan: <feature-id> - <title>
Priority: <N> | Dependencies: <list or "none">

Description:
  <feature description>

Acceptance criteria:
  1. [<type>] <description>
     Verify: <specific command or check>
  2. [<type>] <description>
     Verify: <specific command or check>
  ...

Files to CREATE:
  - <path>
    Purpose: <what this file does>
    Key contents: <function/class names, exports>

Files to MODIFY:
  - <path>
    Change: <exactly what changes and why>
    Criterion satisfied: <which criterion this covers>

Approach:
  <3-5 sentences: implementation strategy, key decisions, patterns to follow>

Edge cases to handle:
  - <edge case and how you'd address it>
  ...

Criteria coverage (every criterion must be mapped):
  - Criterion 1: will pass after <specific change>
  - Criterion 2: already satisfied - <brief explanation>
  ...

Estimated complexity: <Low / Medium / High>
Reason: <brief justification>

Potential risks:
  - <risk and mitigation>
  ...
```

## Step 6: Stop

Do NOT write any code. Do NOT modify any files. Do NOT update writ.json or progress.json.

Output:
```
Plan complete.
To implement: /writ-session <feature-id>
To verify only: /writ-verify <feature-id>
```
