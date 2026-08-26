---
name: micro-change
description: Use when an approved change is one understood code line or visual adjustment with exact focused proof
---

# Micro Change

Implement one approved edit in an isolated worktree. Keep it single-agent. This
route owns implementation, not delivery.

## Eligibility

Use Micro Change only when the approved design names one outcome, its location
and proof are known, and production changes are one code line or one visual
adjustment in one existing component. It cannot change interfaces, data shapes,
schemas, dependencies, configuration contracts, authorization, security,
concurrency, or migrations. Tests and evidence do not count as production
edits. Otherwise, upgrade to Direct Development.

## Workflow

1. Restate the change, proof, and unchanged boundary. Create no temporary plan file.
   Do not request duplicate approval.
2. Use `superpowers:using-git-worktrees` and confirm the named source controls
   the outcome. Do not dispatch subagents.
3. For executed behavior, use `superpowers:test-driven-development`.
   Visual-only changes skip TDD and cannot alter behavior or accessibility.
   Capture authentic before-and-after visual evidence at the same state and
   viewport. Stop if the real UI cannot run.
4. Make one production edit and run its proof and applicable gates. On an
   unexpected failure or second production edit, upgrade to Direct Development.
5. Use `superpowers:verification-before-completion`, show the diff and evidence,
   then use `superpowers:finishing-a-development-branch`.
