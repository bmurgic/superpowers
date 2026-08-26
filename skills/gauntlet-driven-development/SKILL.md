---
name: gauntlet-driven-development
description: Use when executing an approved OpenSpec implementation plan in the current session
---

# Gauntlet-Driven Development

GDD executes one approved OpenSpec vertical slice through its full verification ceremony before any dependent slice starts.
An Implementer report is evidence to inspect, never acceptance.

## Route and setup

Use GDD only for an active OpenSpec implementation with approved `tasks.md` and `plan.md`.
A bare Superpowers plan stops here and invokes `superpowers:subagent-driven-development`.
Do not invoke stock SDD as the controller for an OpenSpec run.

Before the first slice, use `superpowers:using-git-worktrees`, read the approved `tasks.md`, `plan.md`, Gherkin scenarios, and QA procedures, then run `scripts/gdd-workspace PLAN_FILE`.
Create a plan-identified ledger in that workspace and resume from it after interruption.
Record the branch base and each slice's `BASE` before dispatch.
Pinned lifecycle agents receive no model override.
Continue through ready work without routine user pauses, using the ledger, concise file-based briefs and reports, workspace recovery, and bounded escalation to keep context controlled.

`tasks.md` is the canonical visible slice state. Change its exact `**Slice state:**` line and `N.V` gate only through `scripts/gdd-slice-state`; OpenSpec continues to track ordinary `[ ]` and `[x]` checkboxes. Implementers update only their assigned `plan.md` micro-step checkboxes as each step passes local verification. The orchestrator validates report evidence before marking coarse implementation tasks in `tasks.md` `[x]`.

| Moment                | Required evidence                                              |
| --------------------- | -------------------------------------------------------------- |
| Before an Implementer | Recorded `BASE`, task brief, ledger state                      |
| After an Implementer  | Non-empty `BASE..HEAD` range and report evidence               |
| Slice acceptance      | Current Hardener approval, QA `VERIFIED`, final slice suite    |
| Feature acceptance    | Fresh Branch Reviewer and required whole-feature closing steps |

## Slice ceremony

1. Run `scripts/gdd-slice-state PLAN_FILE N implementing`, then extract one brief with `scripts/task-brief PLAN_FILE N`.
2. Dispatch the tagged fresh Implementer with that brief, the actual `PLAN_FILE`, and its report path. The Implementer marks completed micro-steps in its plan section but never edits `tasks.md`.
3. Verify the report and non-empty commit range. Do not accept self-reported completion. Mark each proven coarse implementation task `[x]`, then run `scripts/gdd-slice-state PLAN_FILE N verifying-cleaner IMPLEMENTER_REPORT`.
4. Run one agent at a time in this exact order: `cleaner -> architect -> security-reviewer -> hardener -> e2e-runner [gdd-gate: slice-qa]`. Before each dispatch after Cleaner, advance the state with the prior role's evidence: `verifying-architect`, `verifying-security`, `verifying-hardener`, then `verifying-qa`.
5. Every role receives the slice brief, exact behavior and QA references, current revision, prior verdict or commit, report path, and applicable commands.
6. After QA reports `VERIFIED` against the current Hardener-approved revision, capture the passing final slice suite as a non-empty evidence file containing `Status: PASS`. Run `scripts/gdd-slice-state PLAN_FILE N verified QA_REPORT FINAL_SUITE_REPORT`; this atomically changes the slice state to `[x] VERIFIED` and checks only `N.V`. The next Implementer receives `[gdd-gate: prior-slice-verified]`.

## Findings and replay

A first full-slice pass and a repair replay have different scopes. A repair replay never expands to the whole slice.

When a lifecycle role reports a blocking finding or changes source or tests, record the revision before the first repair commit as `REPAIR_BASE`, then run `scripts/gdd-slice-state PLAN_FILE N repairing FINDING_OR_CHANGE_REPORT`. Dispatch `fixer` for a finding, then `fixer-max` if the same symptom survives. After the repair commits, record `REPAIR_HEAD`, run `scripts/review-package PLAN_FILE REPAIR_BASE REPAIR_HEAD`, then run `scripts/gdd-slice-state PLAN_FILE N verifying-cleaner FIXER_OR_CHANGE_REPORT` before dispatching Cleaner.

Replay only the repair range through the role that caused the repair:

| Repair originated from | Delta-scoped replay roles                                      | Next normal full-slice pass |
| ---------------------- | -------------------------------------------------------------- | --------------------------- |
| Cleaner                | Cleaner                                                        | Architect                   |
| Architect              | Cleaner, Architect                                             | Security Reviewer           |
| Security Reviewer      | Cleaner, Architect, Security Reviewer                          | Hardener                    |
| Hardener               | Cleaner, Architect, Security Reviewer, Hardener                | QA                          |
| QA                     | Cleaner, Architect, Security Reviewer, Hardener                | Fresh QA                    |

Advance `gdd-slice-state` through the same ordered lifecycle states. For every role named in the delta-scoped replay column, dispatch a fresh agent with this exact scope contract:

```text
[gdd-gate: fixer-delta]
Scope: Review only the repair delta. Do not review the whole slice.
Range: REPAIR_BASE..REPAIR_HEAD
Review package: REVIEW_PACKAGE
Replay through: ORIGINATING_ROLE
```

Every replayed role receives the same exact repair range and review package. Fresh means a new agent and verdict; it does not mean whole-slice scope. After the replay reaches its endpoint, later roles continue with their normal first full-slice pass. Do not replay the Implementer or preemptively rerun later lifecycle roles.

If a replayed role causes another fix, keep the original `REPAIR_BASE`, update `REPAIR_HEAD` through the newest repair commit, rebuild the review package, and restart the required delta replay at Cleaner. The endpoint is the later of the existing endpoint and the role that caused the new fix.

QA always runs against the whole current slice. A QA-originated fix invalidates the prior QA result, replays the repair delta through Hardener, then runs one fresh full-slice QA pass. A production behavior change after any QA pass also invalidates that QA evidence.

Keep bounded escalation and ledger entries from the approved plan.

## Feature closing

After every slice is verified, dispatch Branch Reviewer for whole-spec coverage, cross-slice seams, accumulated drift, whole-feature quality, and emergent cross-slice security.
Branch-review fixes replay each affected slice before a fresh Branch Reviewer.
Then, in order, run OpenSpec Verify, retrospective, archive, `superpowers:finishing-a-development-branch`.

## Stop conditions

Stop and escalate before dispatch when the OpenSpec plan, task brief, behavior reference, QA procedure, required current revision, or exact repair range is unavailable.
Do not mark a slice `[x]`, start a dependent Implementer, reuse stale QA, or skip a lifecycle role because of deadline, prior approval, passing focused tests, or user pressure.
Do not continue on a non-empty range without report evidence.

## Rationalizations

| Shortcut                                                 | Required response                                                                                   |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| "Review roles can catch up later."                       | Keep the next slice blocked until the ordered ceremony verifies the current slice.                 |
| "Fresh Security means reviewing the whole slice again." | Fresh means a new agent and verdict. During replay, Security receives only the exact repair range. |
| "The Architect approved before the fix."                 | Replay Cleaner and Architect on the exact repair delta. A pre-fix approval does not cover it.      |
| "Focused tests pass after the authorization fix."        | Replay the exact repair delta through Security, then continue to the first Hardener and QA passes. |
| "QA already passed."                                     | A QA-originated or post-QA production fix requires one new full-slice QA pass after delta replay.  |
| "The browser is unavailable, but acceptance tests pass." | QA cannot report `VERIFIED`. Keep the slice and next Implementer blocked.                           |

## Red flags

- Marking the `N.V` verification gate `[x]` from an Implementer report.
- Editing a `Slice state` line or `N.V` gate without `gdd-slice-state`.
- Starting a dependent slice before `[gdd-gate: prior-slice-verified]`.
- Treating a pre-fix verdict as coverage of the repair delta.
- Giving a replayed role the whole slice instead of the exact repair range.
- Replaying a role after the repair's originating gate before its normal first pass.
- Omitting a required delta replay role or changing the required order.

These mean the slice is still open.
