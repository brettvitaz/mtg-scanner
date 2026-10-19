---
name: feature-review
description: Use when the user explicitly invokes feature-review for an independent read-only correctness review of this branch’s feature changes.
---

# Feature review

An optional brief path may follow this skill. Get an independent review of the feature on this branch, check what the reviewer reports, and report to the user. Do not fix anything.

## Rules

- When you say you will do a step, make the tool call in the same turn. Do not end a turn after only announcing a step.
- Resolve repository-owned skill copies from the task worktree per `AGENTS.md`; preserve this skill's read-only boundary.
- Do not modify project sources or requirements, stage, commit, or stash. Write only review artifacts under `tmp/`.
- Do not inspect other branches, worktrees, or earlier attempts without explicit user authorization. Read only specifically authorized external artifacts; do not modify them.

## Steps

Create a todo list with one item per step before you start, and keep it updated.

1. Load the `requesting-code-review` skill and read its `code-reviewer.md` template, both in full. Follow them, with the changes below.
2. Requirements: read the effective brief and linked authoritative requirements record at the path the user gave, plus explicit later amendments. Stable requirement IDs, source, status and supersession determine the current set; later user corrections override older brief text. For example, a later shared-lens decision supersedes separate lenses, with Station focus constraining the shared policy. Do not reopen that decision or report authorized behavior as a defect. If sources still conflict materially, clarify that conflict while reviewing independent scope; do not edit the record in this read-only phase. Do not pick a file from `tmp/feature-briefs/` yourself, because old briefs from other work can be there. If no path was given, build a numbered requirements list from the commit messages since the merge base, the pull request description (`gh pr view`) if one exists, and any design notes for this feature in `docs/plans/`. Show the list to the user, ask what is missing or wrong, and use the corrected list.
3. Write the diff to a file with git itself, from `BASE=$(git merge-base origin/main HEAD)`. Do not type or copy the diff yourself.
   - `mkdir -p tmp && git diff $BASE -- <feature paths> > tmp/review.diff` covers committed and uncommitted changes to tracked files.
   - For each untracked file from `git ls-files --others --exclude-standard`, append `git diff --no-index /dev/null <file> >> tmp/review.diff`.
   - Leave out paths that are not part of the feature, such as `.pi/`, `tmp/`, or vendored skills. Ask if unsure.
4. Dispatch one reviewer:
   - pi on an omlx model: `subagent({ agent: "reviewer-local", task: <task>, checkpointBeforeDeadlineMs: 300000 })`.
   - pi on a cloud model: the `reviewer` agent.
   - Any other harness: its general-purpose subagent.
   - In pi, call `subagents_enable` first if the `subagent` tool is missing.
   - Do not pass `timeoutMs`. The agent's configured timeout applies, and a local model needs it.
5. Write the reviewer's task from the template:
   - **What Was Implemented:** one sentence from the brief.
   - **Requirements:** absolute paths to the effective brief, requirements record and explicit amendments, identifying effective IDs and superseded entries. Tell the reviewer to read those sources, not a retyped Behavior list that loses corrections.
   - **Brief synchronization:** supplied record path and claimed updated sections/IDs, or the handoff's no-update/no-designated-brief explanation. Have the reviewer inspect the file and compare later approved instructions and material evidence against it. Report stale synchronization as a correctness finding; do not repair it in this read-only phase.
   - **Git range:** replace it with the absolute path of `tmp/review.diff` and tell the reviewer to read that file in full; it is the exact change under review. Do not paste or retype the diff. Give the absolute worktree path so it can read context.
   - **Review focus, only this:** "Does the code correctly implement each requirement, and would a test fail if any requirement broke?" Tell it to skip style unless it hides a bug, and to use `.agents/rules/code-review.md` and `.agents/rules/testing.md` as the standard.
   - Tell it not to run builds or tests. Include the latest check results: from the build handoff if it is in this session, otherwise from the newest check logs in `tmp/` (for example `tmp/final-*.log`), read for exit status and failures. Say which files you read; if there are none, say the checks were not found, not that they failed.
   - Include the build's independent visual-review disposition/report path and its actual scope as external evidence, or explicitly say it is missing. A fix-list verdict is not whole-surface approval. User evidence rejecting an earlier screenshot requires a fresh full finish review through feature-build; this correctness review cannot replace it.
   - Ask only what reading the code can answer. Do not ask whether code compiles, renders, or passes tests.
   - Keep the template's read-only rule, no-subagents rule, "Declined to judge" section, and output format.
6. When the review returns, check each Critical and Important finding yourself by reading the cited code.
7. Report, then stop:
   - Each finding with its severity, `file:line`, and whether you confirmed it, disproved it (with evidence), or could not tell.
   - The reviewer's "Declined to judge" list, unedited.
   - The reviewer's code-correctness verdict, separately from the external visual disposition and outstanding physical acceptance. State missing visual review, missing artifacts, reviewer substitutions and hardware limitations explicitly; code inspection cannot certify rendering, optical sharpness, physical lens selection or framing.
   - A proposed fix for each confirmed Critical or Important finding. Do not apply it.
