---
name: micro-change
description: Use when an approved change is an already-understood one-line code fix or presentation-only visual adjustment with one outcome and exact focused proof
---

# Micro Change

## Overview

Implement one approved, already-understood edit in an isolated worktree. Keep
the work single-agent and prove the exact outcome without creating a plan file.
This route authorizes implementation, not delivery.

## Eligibility

Use Micro Change only when all of these are true:

- The approved design names one falsifiable behavior or visible outcome.
- The production edit is one line or one simple visual adjustment in one
  existing component.
- The exact location and focused proof are already known.
- The change does not alter an interface, data shape, schema, dependency,
  configuration contract, authorization, security boundary, concurrency, or
  migration.

Test and evidence files do not count against the one-production-edit boundary.
If any condition is false or uncertain, upgrade to Direct Development before
editing.

## Workflow

1. Restate the approved change, focused proof, and unchanged boundary in chat.
   Create no temporary plan file and do not request duplicate approval.
2. **REQUIRED SUB-SKILL:** Use superpowers:using-git-worktrees before editing.
3. Confirm the named source location controls the behavior or mounted visual.
   If diagnosis, scope, or proof is uncertain, upgrade to Direct Development.
4. Classify the edit by outcome:
   - **Code change:** Any executed logic or behavior change, even inside a UI
     file. **REQUIRED SUB-SKILL:** Use superpowers:test-driven-development and
     watch the focused regression test fail before editing production code.
   - **Visual-only change:** Presentation changes with no logic, state, event,
     accessibility, or data behavior change. Visual-only changes skip TDD.
     Capture authentic before-and-after visual evidence at the same state and
     viewport. If the real UI cannot run, stop and report the evidence blocker.
5. Make only the approved production edit. Do not dispatch subagents.
6. Run the focused proof and every applicable repository gate. An unexpected
   failure or a second production change ends this route. Stop and upgrade to
   Direct Development.
7. **REQUIRED SUB-SKILL:** Use superpowers:verification-before-completion.
   Show the complete diff and verification evidence, then stop. Do not commit,
   push, file a PR, merge, or discard without a new instruction.

## Quick reference

| Change | Required proof |
|---|---|
| One-line logic or behavior fix | Focused RED-GREEN TDD plus applicable gates |
| Presentation-only visual adjustment | Authentic before-and-after evidence plus applicable gates |
| Unknown cause, wider scope, or unexpected failure | Stop and upgrade to Direct Development |

## Red flags

- Calling a source-file edit visual-only when it changes behavior
- Using line count to admit a security, data, interface, or concurrency change
- Skipping the failing test because the code edit is small
- Replacing authentic visual evidence with a mock or static fixture
- Dispatching a subagent or creating a temporary plan

Any red flag means stop at the current safe state.
