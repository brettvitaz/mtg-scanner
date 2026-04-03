# Plan: Add Work-Effort Documentation Framework

**Planned by:** GitHub Copilot (Claude Opus 4.6)
**Date:** 2026-04-03

## Approach

Create the four template files first (request, plan, log, review), then the supporting documentation (README, PROMPTS, ORCHESTRATION, CLAUDE.md), then the shell script, then a retrospective work effort as the first real example. Templates use `[FILL:]` placeholders so agents do slot-filling rather than generative document creation. Log format uses headings + paragraphs instead of tables for weak-model compatibility.

## Implementation Steps

1. Create `docs/work-efforts/templates/` directory and four template files (parallel)
2. Create `docs/work-efforts/README.md` — convention overview (depends on step 1 for file references)
3. Create `docs/work-efforts/PROMPTS.md` — agent prompt blocks (parallel with step 2)
4. Create `docs/work-efforts/ORCHESTRATION.md` — human workflow guide (parallel with steps 2-3)
5. Create `docs/work-efforts/CLAUDE.md` — standalone snippet (parallel with steps 2-4)
6. Create `scripts/new-work-effort.sh` — scaffolding script (parallel with steps 2-5)
7. Test the shell script: happy path, duplicate, no args, invalid slug, number prefix
8. Create retrospective work effort using the script (depends on steps 1-7)

## Files to Modify

| File | Change |
|------|--------|
| `docs/work-efforts/templates/request.md` | New — human-authored template |
| `docs/work-efforts/templates/plan.md` | New — agent planning template |
| `docs/work-efforts/templates/log.md` | New — agent logging template |
| `docs/work-efforts/templates/review.md` | New — agent review template |
| `docs/work-efforts/README.md` | New — convention and usage guide |
| `docs/work-efforts/PROMPTS.md` | New — copy-pasteable agent prompts |
| `docs/work-efforts/ORCHESTRATION.md` | New — human orchestration guide |
| `docs/work-efforts/CLAUDE.md` | New — standing agent instructions |
| `scripts/new-work-effort.sh` | New — shell script for scaffolding |
| `docs/work-efforts/2026-04-03-add-work-effort-framework/` | New — retrospective example |

## Risks and Open Questions

- The `sed -i ''` syntax is macOS-specific. Linux uses `sed -i` without the empty string arg. Accepted for now since the project is macOS-focused.
- The slug duplicate check uses `find` with a glob. If the work-efforts directory grows to thousands of entries, this could be slow. Unlikely to be a problem in practice.

## Verification Plan

1. Run `./scripts/new-work-effort.sh test-slug` — verify folder and file creation
2. Run it again — verify duplicate rejection
3. Run with no args — verify usage message
4. Run with `INVALID_SLUG` — verify kebab-case rejection
5. Run with `123-starts-with-number` — verify number prefix is accepted
6. Grep all templates for `[FILL:]` — verify all have placeholders
7. Verify log.md in created efforts has no example entry
8. Verify PROMPTS.md and ORCHESTRATION.md have proper content separation
