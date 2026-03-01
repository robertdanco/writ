---
description: Show project progress dashboard - features completed, pending, blocked, and next up
allowed-tools: Read, Bash, Glob, Grep
---

Display a progress dashboard for the current SDD project. Does not modify any files.

## Instructions

1. Read `spec.json`. If not found, output "No spec.json found. Run /sdd-ingest first." and stop.

2. Read `progress.json`. If not found, treat all features as having no recorded sessions.

3. Run `git log --oneline -5 2>/dev/null || echo "(no commits)"` to get recent history.

4. Compute the following from spec.json:
   - Total feature count
   - Count by status: completed, in_progress, pending, blocked
   - Count by priority tier
   - Which pending features are ready (all depends_on are completed)
   - Which pending features are blocked (depends_on not all completed)

5. Output the dashboard in this format:

```
Project: <name>
<description if present>
═══════════════════════════════════════════════════
Features:  <N> total | <X> done | <Y> pending | <Z> in_progress
Progress:  [<filled bar>] <pct>%

Last session: <progress.json last_session.date> - <feature_id>
              "<summary>"
Last commit:  <git log first line>

By priority:
  P1 (must-have):    <X>/<N> complete
  P2 (important):    <X>/<N> complete
  P3-5 (optional):   <X>/<N> complete

Ready to implement:
  - <feature-id>: <title> (P<N>)
  - <feature-id>: <title> (P<N>)
  ...

In progress:
  - <feature-id>: <title> (started <date if known>)

Blocked (waiting on dependencies):
  - <feature-id>: waiting on <dep-id>, <dep-id>
  ...

Completed (<N> total):
  <list feature-ids, 5 per line>
═══════════════════════════════════════════════════
Next up: <feature-id> - <title>
Run /sdd-session to continue.
```

Progress bar: use `█` for filled, `░` for empty, 20 chars wide.
Example: `[████████░░░░░░░░░░░░] 40%`

If no features are ready (all remaining blocked), output:
```
WARNING: All remaining features are blocked by incomplete dependencies.
Dependency chain: <show the blocking chain>
```

If all features are completed, output:
```
ALL FEATURES COMPLETE
Total sessions: <sum of sessions across progress.json>
Run: git log --oneline to review committed work.
```

## Rules

- Do not modify any files.
- If progress.json has no entry for a feature, omit it from session counts.
- Priority tiers: P1 = priority 1, P2 = priority 2, P3-5 = priority 3, 4, or 5.
- Sort "Ready to implement" by priority ascending, then by spec.json order.
