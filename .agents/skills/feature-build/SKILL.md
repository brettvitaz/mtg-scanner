---
name: feature-build
description: Implement an approved feature brief written by feature-design, verify it against the repository's checks, commit it, and hand it off for review. Use only when the user invokes this skill with a brief path.
---

# Feature build

The path to an approved brief follows this skill. Use only a brief path the user gives. If there is none, ask for it; do not pick a file from `tmp/feature-briefs/` yourself, because old briefs from other work can be there. Implement only the approved design, and do not change it on your own. If something in it cannot be built as approved, stop and ask. If an item can be built but cannot do what it is for (for example, a test that no code change could make fail), build the rest, then report that item in the handoff with the reason and a proposed fix.

## Rules

- When you say you will do a step, make the tool call in the same turn. Do not end a turn after only announcing a step.
- Work only in the current worktree. Do not look at other branches, other worktrees, or earlier attempts at this feature.
- The root `AGENTS.md` is already in your context. Do not read it again.
- Run every check in the foreground with output in a log file, then report the exit code. Never pipe a check through `tail` or `head`.

## Steps

Create a todo list with one item per step before you start, and keep it updated.

1. Read the brief in full. Then read, as whole files, the nested `AGENTS.md` and the `.agents/rules/` files for each subsystem the brief touches, plus `.agents/rules/testing.md` and `.agents/rules/code-review.md`.
2. Run `git fetch origin` and `git rev-list --left-right --count HEAD...origin/main`. If this branch is behind `origin/main`, tell the user. Do not rebase without asking.
3. Baseline. Run the checks `AGENTS.md` lists for each touched subsystem, one at a time, each to its own log, for example `make ios-test > tmp/baseline-ios-test.log 2>&1; echo "exit=$?"`. Record any failures. Do not edit code until every baseline check has finished.
4. Implement the brief yourself, in this session, including every test in its Test map. Do not hand the implementation to a subagent. If a subagent is used for anything else, give it file paths to read; never retype or paste the brief or a diff.
5. Review the implementation yourself: `git diff`, plus `git status --short` for new files. Confirm that every Behavior item has the test named in the Test map, and that the code change the Test map names would make that test fail. Add any missing tests.
6. Visual check, for UI changes. Add each snapshot route from the brief, following all five steps of "Adding a new route" in `apps/ios/AGENTS.md`. Run `make ios-snapshot ROUTE=<name>`, open each PNG with your read tool, and describe what you see. Fix anything that does not match the brief.
7. Update the docs listed in the brief, and any other docs whose described behavior or configuration changed.
8. Final checks: rerun the baseline checks to new log files, then `git diff --check`.
9. Run `git status --short`. Every changed or new path must be part of this feature. List any that are not, and do not delete them without asking.
10. Go through `.agents/rules/code-review.md` one criterion at a time: PASS, FAIL, or N/A with a reason. Fix every FAIL this change caused, then rerun the affected checks.
11. Commit the feature's changes with messages that say what changed and why. Several commits are fine, since PRs are squash-merged. Do not include unrelated changes in them; list anything unrelated in the handoff instead.
12. Hand off with:
    - Absolute worktree path, branch, and commit hashes.
    - A table of Behavior item, its test, and the result.
    - Baseline and final check results, with log paths.
    - Snapshot PNG paths.
    - Every deviation from the brief, and why.
    - Brief items that cannot do what they are for, each with a proposed fix.
    - Anything unverified.
    - Commands to inspect or run the change.
    - The next step: `/skill:feature-review` in pi, or `$feature-review` in Codex.
