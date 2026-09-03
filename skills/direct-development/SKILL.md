---
name: direct-development
description: Use when a localized change has selected Direct Development and does not need the ceremony of an OpenSpec change or a multi-task Superpowers plan.
---

# Direct Development

Implement one approved bounded design without an OpenSpec change or multi-task
plan. `superpowers:brainstorming` owns inspection and approval. This skill owns
execution, not delivery.

## Persist the design

Before editing, save the approved design outside the repository for compaction
recovery:

```bash
plan_dir="$(mktemp -d "${TMPDIR:-/tmp}/direct-development.XXXXXX")"
plan_path="$plan_dir/<descriptive-slug>.md"
```

Keep the file freeform and omit status or route bookkeeping. Include context
and this summary, then show both in chat:

```text
Plan: /absolute/path/to/plan.md

Change: One falsifiable behavior or visible outcome.
Touch: The likely files or components and narrow implementation approach.
Verify: Focused tests, repository gates, and visual proof when the UI changes.
Boundary: Behavior and areas that must remain unchanged.
```

If the design is not approved, add `Proceed?` and stop. If already approved,
do not ask again. Reuse a supplied approved path instead of recreating it. When
new facts materially change scope, proof, or boundaries, update the same file,
show the revised summary with `Proceed?`, and stop. Return to brainstorming if
the change is no longer localized.

## Workflow

1. Read the plan, then use `superpowers:using-git-worktrees` before editing.
2. Use `superpowers:systematic-debugging` for an undiagnosed bug or unexpected
   failure.
3. Use `superpowers:test-driven-development` for behavior changes and bug fixes.
   For non-executable documentation or configuration, define deterministic
   proof before editing.
4. Implement only the approved design.
5. Reread the plan, run its proof and applicable repository gates, then use
   `superpowers:verification-before-completion` and commit.
6. Use `superpowers:finishing-a-development-branch` and wait for its delivery
   choice.

Direct Development never grants permission to push, open a PR, merge, or
discard work.
