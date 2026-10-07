---
name: feature-design
description: Design a feature for this repository with the user and get explicit approval before any code changes, then save the approved design as a brief for feature-build. Use only when the user invokes this skill with a feature request.
---

# Feature design

The user's feature request follows this skill. Agree on a design with the user, get explicit approval, and save the approved design as a brief that `feature-build` implements. Do not change product code in this phase.

## Rules

- When you say you will do a step, make the tool call in the same turn. Do not end a turn after only announcing a step.
- Work only in the current worktree. Do not look at other branches, other worktrees, or earlier attempts at this feature.
- The root `AGENTS.md` is already in your context. Do not read it again.
- Every statement about how the current code behaves must cite a `file:line` you read in this session. Label anything you have not checked as "unverified".
- Ask questions about what the user will see or do. Do not phrase questions in terms of APIs, types, or files. Implementation choices are yours to make; report them in the design.
- Do not ask again about anything already in the Decisions list.

## Steps

Create a todo list with one item per step before you start, and keep it updated.

1. Read these in full, as whole files with no line ranges:
   - The nested `AGENTS.md` for each subsystem the feature touches (`apps/ios/AGENTS.md`, `services/api/AGENTS.md`).
   - The `.agents/rules/` files that the root `AGENTS.md` routes to for those subsystems, plus `.agents/rules/testing.md`.
   - `PRODUCT.md`.
2. Read the code the feature will change.
3. If the feature changes UI, load the `impeccable` skill before presenting a design. Run its setup step, `.agents/skills/impeccable/scripts/impeccable context --target <main file you will change>`, follow its directives, then follow `reference/shape.md` and any platform reference it points to.
4. Ask clarifying questions, one question per message, and wait for each answer before asking the next. Never list several questions at once. Use the harness's question tool when it has one: `ask_user_question` in pi, `request_user_input` in Codex (available in Plan mode). Otherwise ask in plain text. Where there is a real choice, offer two or three options with a recommendation, as multiple choice when the tool supports it. After each answer, add it to a **Decisions** list, quoting the user's words. Stop asking when the user-visible behavior is settled.
5. Present the design with these sections:
   - **Decisions**: the list from step 4, word for word.
   - **Behavior**: a numbered list of what the user will see and do. These are the requirements.
   - **Code changes**: files and what changes in each, with `file:line` evidence for every claim about existing code.
   - **Test map**: for each Behavior number, the test that will fail if that behavior breaks, and the code change that would make it fail (for example, "remove the reset in `clearCount()`"). If no code change the test can reach would make it fail, it is not a test for that behavior; find another. For purely visual behavior, name the snapshot route instead.
   - **Visual check**: for UI changes, the snapshot fixture routes to add (see "Adding a new route" in `apps/ios/AGENTS.md`) and the state each one shows. Say which screen each route opens on, and check that opening that screen does not change the state the route is meant to show.
   - **Docs**: files to update.
   - **Additions I propose (need approval)**: anything not covered by Decisions. Write "None" if empty.
   - **Unverified**: claims you have not checked against the code.
6. Stop and wait for approval. If the user changes anything, update the design and present it again.
7. After approval, write the brief to `tmp/feature-briefs/<short-name>.md` (`tmp/` is gitignored). Include the original request word for word, then the Decisions, Behavior, Code changes, Test map, Visual check, and Docs sections as approved, with every change the user made. Tell the user the path and the next step: `/skill:feature-build tmp/feature-briefs/<short-name>.md` in pi, or `$feature-build` with the path in Codex.
