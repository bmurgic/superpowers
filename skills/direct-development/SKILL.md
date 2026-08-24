---
name: direct-development
description: Use when a localized change has selected Direct Development and does not need an OpenSpec change or a multi-task Superpowers plan
---

# Direct Development

## Overview

Implement one bounded change without a multi-task lifecycle plan. Save the
approved design outside the repository for compaction recovery. This route
authorizes implementation, not delivery.

## Design and approval

`superpowers:brainstorming` owns inspection, the bounded design, and its
approval. Direct Development does not repeat that work.

Before creating a worktree or editing source, save the bounded design in one
freeform Markdown file:

```bash
plan_dir="$(mktemp -d "${TMPDIR:-/tmp}/direct-development.XXXXXX")"
plan_path="$plan_dir/<descriptive-slug>.md"
```

Include context, the change, likely paths or symbols, verification, and the
boundary. Omit status and route bookkeeping. Show the full path and the same
high-level design in chat:

```text
Plan: /absolute/path/to/plan.md

Change: One falsifiable behavior or visible outcome.
Touch: The likely files or components and narrow implementation approach.
Verify: Focused tests, repository gates, and visual proof when the UI changes.
Boundary: Behavior and areas that must remain unchanged.
```

If the design is not approved, add `Proceed?` and stop. If the same design was
already approved before Direct Development was selected, show the path and
summary without asking for duplicate approval.

If new facts materially change scope, proof, or boundaries, update the same
file, show the refreshed summary with `Proceed?`, and stop. If the change is no
longer localized, return to brainstorming for a different route.

## Workflow

1. Read the plan file before creating a worktree. State:
   `Direct Development - approved localized change; no ADR or specification change.`
2. **REQUIRED SUB-SKILL:** Use superpowers:using-git-worktrees before editing.
3. For an undiagnosed bug, **REQUIRED SUB-SKILL:** Use
   superpowers:systematic-debugging, then return with an evidence-backed design.
4. For behavior changes and bug fixes, **REQUIRED SUB-SKILL:** Use
   superpowers:test-driven-development before implementation. For
   non-executable documentation or configuration, define deterministic proof
   before editing.
5. Implement only the approved design.
6. On an unexpected test, gate, or behavior failure, **REQUIRED SUB-SKILL:** Use
   superpowers:systematic-debugging before proposing a fix.
7. Reread the plan before final verification. Run its proof and every applicable
   repository gate.
8. **REQUIRED SUB-SKILL:** Use superpowers:verification-before-completion, then
   commit the verified change.
9. **REQUIRED SUB-SKILL:** Use superpowers:finishing-a-development-branch.
   Present its menu and wait. Do not push, open a PR, merge, or discard before
   selection.

For the PR option, `file-pr` owns its contents and `gh-axi` owns GitHub work.

## Quick reference

| State | Action |
|---|---|
| Design unapproved | Show path and summary, ask `Proceed?`, then wait |
| Same design already approved | Show path and summary, continue without a second approval |
| Supplied approved path | Read and revalidate it; do not recreate or reapprove it |
| Design no longer fits | Update the file and request approval again |
| Behavior changes | TDD at the closest runnable layer |
| Unexpected failure | Systematic debugging |
| Verified implementation | Commit, then run branch finishing |

## Red flags

- Starting implementation without an approved bounded design
- Treating the temporary file as a second planning cycle
- Treating Direct Development as permission to push or file a PR
- Claiming completion before fresh verification

Any red flag means stop at the current safe state.
