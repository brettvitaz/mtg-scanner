# Request: Add Work-Effort Documentation Framework

**Date:** 2026-04-03
**Author:** brettvitaz

## Goal

Create a lightweight documentation framework that produces a traceable chain from "what was asked" → "what the agent planned" → "what actually happened" → "did it match." It must work across multiple repos, survive weak models, and keep human-authored content separate from agent-authored content.

## Requirements

1. `docs/work-efforts/templates/` contains four files: `request.md`, `plan.md`, `log.md`, `review.md` — all with `[FILL:]` placeholders.
2. `docs/work-efforts/README.md` explains the convention and usage for both human reviewers and code review agents.
3. `docs/work-efforts/PROMPTS.md` contains clean, copy-pasteable prompt blocks for Phases 1-4 with no human orchestration guidance mixed in.
4. `docs/work-efforts/ORCHESTRATION.md` contains the human workflow guide, phase gate verification steps, and the workflow diagram.
5. `docs/work-efforts/CLAUDE.md` contains a standalone snippet with standing instructions for all three agent phases that can be merged into an existing CLAUDE.md.
6. `scripts/new-work-effort.sh` creates a correctly named folder, copies all four templates, cleans log.md, and prints the path to request.md.
7. The script validates slug format (kebab-case), rejects duplicates, and prints usage on missing arguments.
8. Template design accounts for weak models: slot-filling over generation, simple log format, phase separation so each task is narrow.
9. A completed retrospective work effort exists as a working example of the system.

## Scope

**In scope:**
- Template files with `[FILL:]` placeholders
- README, PROMPTS, ORCHESTRATION, and CLAUDE.md documentation
- Shell script for scaffolding new work efforts
- A retrospective work effort as a real example

**Out of scope:**
- Modifying the top-level CLAUDE.md or AGENTS.md (snippet is standalone)
- Makefile targets for the script
- CI integration or automation
- Editor integration beyond printing the path

## Verification

1. `./scripts/new-work-effort.sh test-slug` creates the correct folder with four files
2. Duplicate slugs are rejected
3. No-arg invocation prints usage
4. Invalid slugs (uppercase, underscores) are rejected
5. `log.md` in created efforts has no example entries
6. All templates contain `[FILL:]` placeholders
7. PROMPTS.md has no orchestration text; ORCHESTRATION.md has no raw prompts
8. CLAUDE.md snippet is self-contained

## Context

Files or docs the agent should read before starting:

- docs/feature-workflow.md
- .claude/rules/code-review.md
- scripts/bootstrap-api.sh (shell script style reference)

## Notes

Design decisions:
- Log uses headings + paragraphs instead of tables for weak-model compatibility.
- Script prints path instead of opening an editor — safe for agents and CI.
- CLAUDE.md is a separate portable snippet, not merged into top-level project files.
