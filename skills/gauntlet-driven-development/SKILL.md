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

Before the first slice, use `superpowers:using-git-worktrees` and read the approved `tasks.md`, `plan.md`, Gherkin scenarios, and QA procedures.
Resolve the OpenSpec change directory from `PLAN_FILE`, then run `scripts/gdd-readiness CHANGE_DIRECTORY`. A nonzero result stops before workspace creation, slice-state mutation, or agent dispatch and returns every reported defect to planning. Standard OpenSpec validation does not replace this check.
Then run `scripts/gdd-workspace PLAN_FILE`.
Then run `scripts/gdd-workflow-state PLAN_FILE init`. Read the workspace's pinned
`finding-policy.md` once. Resume only when its saved policy digest matches the
saved snapshot.
`gdd-finding-state PLAN_FILE init` is not the controller entry point; its
finding commands remain receipt-bound adapters inside the workflow loop.
Create a plan-identified ledger in that workspace and resume from it after interruption.
Record the branch base and each slice's `BASE` before dispatch.
Pinned lifecycle agents receive no model override.
Continue through ready work without routine user pauses, using the ledger, concise file-based briefs and reports, workspace recovery, and bounded escalation to keep context controlled.

## Obligation controller loop

The workflow-state reducer, not the controller's own reconstruction, decides
the next lifecycle step. Every dispatch and local lifecycle action enters
through this loop:

1. Run `scripts/gdd-workflow-state PLAN_FILE next`.
2. If it returns `READY`, write the exact dispatch or local action evidence.
3. After `next` returns `READY`, claim the returned obligation before dispatch.
4. Issue the action and record its actual result.
5. Through its matching adapter, accept only the receipt-bound result.
6. Without a user pause, continue while a ready obligation exists.
7. Stop only for `INVALID`, `USER_AUTHORITY_REQUIRED`, or `COMPLETE`.

When `next` returns `RESUME_CLAIM`, resume the recorded agent when the harness
still exposes it. Otherwise reissue the same bounded action with the same
receipt. Do not claim a replacement obligation. `USER_AUTHORITY_REQUIRED` is
machine-derived and appears only when no claim or ready obligation remains.
Fable unavailability blocks the finding on its gating boundary. The reducer
requests user authority once no other ready obligation remains.

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
4. Run one agent at a time in this exact order: `cleaner -> architect -> security-reviewer -> hardener -> e2e-runner [gdd-gate: slice-qa]`. Before each dispatch after Cleaner, advance the state with the prior role's evidence and that role's `FINDINGS_DIR`: `verifying-architect`, `verifying-security`, `verifying-hardener`, then `verifying-qa`. Pass the QA `FINDINGS_DIR` with its final-suite evidence to `verified` so QA, its findings, the final suite, and verification remain one transaction.
5. Every lifecycle role receives the slice brief, exact behavior and QA references, current revision, prior verdict or commit, report path, applicable commands, and this exact addendum. Do not add it to Fixer or Fixer Max, which receive only a finding already in `REPAIRING`.

```text
[gdd-finding-report]
Report every technical finding. Do not choose the workflow disposition.
Write `Finding count: N` in the role report. For each finding, write one
numbered finding file under FINDINGS_DIR using the ten fields below. Use zero
only when the role found no technical issue.
For each finding, write these fields: Origin role, Severity claim, Blocking
claim, Observed failure, Evidence, Violated authority, Assumptions, Failure
scenario, Proposed repair, and Repair effects. Keep your technical gate verdict
independent from the controller's later ruling.
```

This contract applies to Cleaner, Architect, Security Reviewer, Hardener, QA,
and Branch Reviewer. Role status is evidence, not routing authority. Hardener
and QA verification statuses remain binding for their own gates.
The role adapter rejects a count that does not match the files, a duplicate
number, an unexpected file, or an origin that differs from the claimed role.
It accepts the role result and all `FindingReported` events in one transaction,
so the role boundary cannot advance between them.
6. After QA reports `VERIFIED` against the current Hardener-approved revision, capture the passing final slice suite as a non-empty evidence file containing `Status: PASS`. Run `scripts/gdd-slice-state PLAN_FILE N verified QA_REPORT FINAL_SUITE_REPORT FINDINGS_DIR`; this atomically changes the slice state to `[x] VERIFIED` and checks only `N.V`. The QA result, its findings, the final suite, and verification are one transaction. The next Implementer receives `[gdd-gate: prior-slice-verified]`.

## Findings and replay

A first full-slice pass and a repair replay have different scopes. A repair replay never expands to the whole slice.

For every lifecycle finding, the controller:

1. Reads the complete role report without reacting.
2. Restates each finding as one falsifiable technical claim.
3. Accepts the role result through its grouped lifecycle adapter. That adapter assigns Finding IDs, derives the role scope, validates the complete numbered files, and appends every `FindingReported` event with the role result before changing the slice boundary. Use the current slice number for slice roles and `feature` for Branch Reviewer.
4. Verifies the evidence against the code, approved artifacts, actual operating context, and explicit non-goals.
5. Tests every assumption and threat premise. Ask the reporting role for missing context instead of guessing.
6. Decides whether the claim is binding, in scope, dependent, and repairable.
7. Records the disposition, Ruling, Cost if wrong, Fable evidence when required, and Wake condition.

When a role omits information it cannot establish, record its partial report
immediately, investigate the missing field, and run `scripts/gdd-finding-state PLAN_FILE supplement FINDING_ID REPORT_FILE` with the verified value or
`N/A: <reason>` before any disposition or repair transition. Never reject or
drop the original finding because its first report is incomplete.

Use the policy snapshot for every ruling. Its finding states are `REPORTED`,
`REPAIRING`, `RESOLVED`, `DEFERRED`, `DISMISSED`, `PARKED`, and `BLOCKED`.
`REPORTED`, `REPAIRING`, and `BLOCKED` stop the relevant lifecycle boundary.
Every other finding receives a disposition and the run continues unless an
interruption condition below applies.

Interrupt only when completion is not defensible:

1. An accepted requirement cannot be satisfied without choosing new behavior.
2. A dependent slice would build on a known-invalid interface or premise.
3. Continuing would create destructive, irreversible, or Critical in-scope harm.
4. Approved artifacts contradict each other and provide no compliant path.
5. Required acceptance evidence cannot be produced.

Before `DEFERRED`, `DISMISSED`, `PARKED`, `BLOCKED`, or a scope-expanding
repair, invoke `fable-advisor:advise` with the finding, approved artifacts,
verified facts, assumptions, proposed disposition, cost if wrong, and repair
history. Record an unavailable consultation exactly as `Fable result:
UNAVAILABLE: <reason>`. Fable is advisory. Approved artifacts and explicit user
decisions remain authoritative.

### Completion record

Complete every finding scenario as an execution record, not a proposed workflow.
Append each record at the execution point for its command, result, or dispatch.
Do not reconstruct the sequence after later work finishes.
Preserve the originating role's `Technical verdict:`, `Severity claim:`, and
`Blocking claim:` as evidence while the controller chooses the disposition.

### Per-finding execution record

For every finding, complete these literal fields in this order. Copy the first four values from the role report without paraphrasing. The controller owns the
remaining values and chooses the disposition independently.

```text
Originating role: <role>
Technical verdict: <literal role verdict>
Severity claim: <literal role severity>
Blocking claim: <literal role blocking claim>
Finding ID: <ID>
Verified claim: <falsifiable claim and evidence result>
Fable result: <actual advisory result>
Fable gate: NOT REQUIRED: <evidence-backed checked conditions>
Disposition: <state transition and outcome>
Ruling: <controller ruling>
Cost if wrong: <concrete consequence>
Wake condition: <observable condition>
Mandatory gates: Hardener mutation evidence remains mandatory; QA acceptance evidence remains mandatory.
Digest retention: <retained unchanged or N/A because RESOLVED>
Issued next dispatch: <actual issued lifecycle or dependent dispatch, or STOPPED: interruption condition>
```

Use exactly one Fable field. `Fable result:` is required when the policy gates
the ruling. Otherwise use `Fable gate: NOT REQUIRED:` and name the verified
conditions that excluded every gate. `UNAVAILABLE` is valid only after an actual `fable-advisor:advise` invocation fails.
Prompt constraints, test fixtures, and lack of shell execution do not prove unavailability.

The mandatory-gates field is literal for both continuing and stopped paths.
For an unchanged disposition, the digest field records retention and the issued
`digest` command. For `RESOLVED`, record the stated N/A value. An issued-dispatch
field contains the actual dispatch and its outcome, not a plan or template.

Do not end the controller turn at a Fable request, a `REPORTED` finding, or
a future-tense dispatch template. A consultation counts only after its actual
result is recorded; a dispatch or transition counts only when its issued
record and outcome are present. Continue controller work after each result
unless an interruption condition applies.

1. For every Fable-gated ruling, record its actual advisory result. If an actual
   invocation fails, record `Fable result: UNAVAILABLE: <failure>`.
   When Fable is unavailable, `BLOCKED` is required. Its `Blocked boundary:`
   is the next lifecycle obligation the ruling gates: the next `slice-N-<role>`
   obligation for a slice finding, or `feature-findings-digest` for a Branch
   Reviewer finding. Continue every other ready obligation, then stop at
   `USER_AUTHORITY_REQUIRED` and present the finding to your human partner.
   Their ruling returns the finding to `REPORTED` with a `Wake evidence:`
   artifact. Record the later disposition with `User authority: <file>` holding
   that ruling when Fable is still unavailable. For a repair with no
   Fable gate, record `Fable gate: NOT REQUIRED: <checked conditions>`.
2. Use the ordered slice-repair execution record below for ordinary repairs.
   Final-wave repairs use the stricter order below.
3. After every non-blocking disposition, issue the next eligible lifecycle or
   dependent dispatch. When a woken finding stops dependent work, issue the dependent dispatch in the same controller turn after `RESOLVED`
   once the boundary is eligible. A woken finding's dependent dispatch must contain its Finding ID, Ruling,
   Cost if wrong, and Wake condition. The issued dispatch includes the Finding ID, prior Ruling, Cost if wrong, and Wake condition. Every unchanged
   disposition records final-digest retention and the `digest` command in the
   same execution record.
4. A stopped or `BLOCKED` boundary does not waive Hardener mutation evidence or
   QA acceptance evidence. Record: `Hardener mutation evidence remains mandatory;
   QA acceptance evidence remains mandatory.` Record the stopped
   boundary and missing gate or authority. Before ending at a stopped boundary,
   adjudicate every recorded finding under this policy and retain every
   unchanged finding for the final digest.

### Ordered slice-repair execution record

Append these entries at their execution points in exactly this order:

1. `repair-start`: command, outcome, round, executor, hypothesis, repair base,
   and replay endpoint.
2. `Issued fixer dispatch:` actual dispatch content and accepted agent identity.
3. `Originating replay endpoint:` each ordered replay command, role dispatch,
   and outcome through the originating role.
4. `repair-finish`: command and verified outcome at the replay endpoint.
5. `RESOLVED`: explicit `REPAIRING -> RESOLVED` transition.
6. `Remaining first-pass lifecycle gates:` every later required role dispatch
   and outcome, including Hardener and QA when they follow the endpoint.
7. `Passing final-suite evidence:` current revision, evidence path, and
   `Status: PASS` result after required Hardener and QA evidence.

Do not issue or record any later item before the previous item succeeds.
A repair record records the `repair-finish` command before the explicit
`REPAIRING -> RESOLVED` transition. A final-wave record places every affected-slice replay endpoint before
`repair-finish`, `RESOLVED`, and one fresh whole-branch Branch Reviewer, in
that order.

Before each later dispatch, check wake conditions for findings that touch the
same code, interface, task dependency, or changed premise. Include each
matching Finding ID, Ruling, Cost if wrong, and Wake condition in the dispatch.
Return a woken finding to `REPORTED` with a `Wake evidence:` artifact before
dependent work starts.

For one slice finding in `REPAIRING`, keep the original `REPAIR_BASE`, rebuild
the review package through the newest `REPAIR_HEAD`, and restart the exact-delta
replay at Cleaner. Round 1 uses `fixer`. Rounds 2 through 5 use a fresh `fixer-max`.
Every later round needs new evidence or a different falsifiable
hypothesis. Resolve the finding only after the replay reaches its recorded
endpoint. Stop the loop when replay passes or when no different credible repair
remains.

For a repairable finding, record the revision before the first repair commit as
`REPAIR_BASE`, transition the finding to `REPAIRING`, then run
`scripts/gdd-slice-state PLAN_FILE N repairing FINDING_REPORT FINDING_ID` before
dispatching its fixer. After the repair commits, record `REPAIR_HEAD`, run
`scripts/review-package PLAN_FILE REPAIR_BASE REPAIR_HEAD`, then run
`scripts/gdd-slice-state PLAN_FILE N verifying-cleaner FIXER_REPORT` before
dispatching Cleaner.

Before each fixer dispatch, run `scripts/gdd-finding-state PLAN_FILE repair-start FINDING_ID REPAIR_START_EVIDENCE` with the next sequential round,
required executor tier, fresh agent ID, hypothesis, repair base, and replay
endpoint. After the repair and independent replay, run `scripts/gdd-finding-state PLAN_FILE repair-finish FINDING_ID REPAIR_FINISH_EVIDENCE`.
Do not start rounds 2 through 5 until the prior result
is `FAILED`; never dispatch round 6. Transition to `RESOLVED` only after the
latest recorded attempt is `VERIFIED`. This repair history is the authoritative
source for every commit range handed to later review.

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

After every slice is verified, dispatch Branch Reviewer for whole-spec coverage,
cross-slice seams, accumulated drift, whole-feature quality, and emergent
cross-slice security. Its brief contains the full branch review package, the
approved OpenSpec artifacts, and every unchanged finding with its Finding ID,
Ruling, Cost if wrong, and Wake condition.

Record new Branch Reviewer findings with scope `feature`. For each repairable
new or woken final finding, transition it to `REPAIRING` with a normalized
`Affected slices:` list and the same normalized `Final wave findings:` list.
The engine derives one immutable final-wave identity from that complete finding
list. Each finding keeps its own accepted slice membership, while every finish
and resolution waits for the wave-wide affected-slice union. Record each repair
start, then send all repairable final findings in one fix dispatch. The same
actual fixer identity may be recorded once on each finding in the one combined
fix dispatch.

### Final-wave dispatch order

Record the final-wave execution boundary in this stricter order:

1. `Issued combined fixer dispatch:` actual dispatch for every final finding in
   `REPAIRING`, with the accepted agent identity recorded on each finding.
2. `Affected-slice replay:` each issued Cleaner, Architect, Security Reviewer,
   Hardener, and QA dispatch and outcome for every affected slice.
3. `Passing final-suite evidence:` current revision, evidence path, and
   `Status: PASS` result for every affected slice.
4. `repair-finish`: command and verified outcome for each final finding.
5. `RESOLVED`: explicit `REPAIRING -> RESOLVED` transition for each finding.
6. `Fresh whole-branch Branch Reviewer:` actual dispatch and outcome.

Record that dispatch at its execution point before any replay command. A fixer
dispatch written after replay is a retrospective template and does not count.

After that dispatch returns, call `scripts/gdd-slice-state PLAN_FILE N repairing
FINDING_REPORT FINDING_ID` for every affected verified slice. Replay every
affected slice through Cleaner, Architect, Security Reviewer, Hardener, QA, and
its final suite with fresh evidence. Record repair-finish only after every affected slice reaches its replay endpoint.
Then record `repair-finish` for
each finding with the combined repair head and that finding's replay evidence,
and transition each independently verified finding to `RESOLVED`.

Run one fresh whole-branch Branch Reviewer. Adjudicate residual findings without
a second final fix wave. There is no second final fix wave. Claim the digest
obligation, then run `scripts/gdd-workflow-state PLAN_FILE digest OUTPUT_FILE`.
It reads reduced state and writes every unchanged deferred, dismissed, and
parked finding with its Finding ID, origin, ruling, cost if wrong, wake
condition, and evidence digest. It accepts `FindingsDigestWritten` through the
active receipt. Append the digest's `Findings left unchanged` section to the
retrospective before archive.

Claim the completion obligation and run
`scripts/gdd-workflow-state PLAN_FILE complete EVIDENCE_FILE`. It succeeds only
when the reducer reports no unsatisfied required obligation and writes:

```text
Workflow status: COMPLETE
Workflow revision: ${revision}
Journal head SHA-256: ${event_hash}
Branch review evidence: ${branch_review_evidence_path}
Findings digest: ${digest_path} ${digest_sha256}
```

Completion evidence: pass that completion path and the findings digest to
`superpowers:finishing-a-development-branch`. Then, in order, run OpenSpec
Verify, retrospective, archive, `superpowers:finishing-a-development-branch`.

The fresh post-wave Branch Reviewer brief includes the full branch review
package, approved OpenSpec artifacts, and every woken final finding's Finding
ID, original Ruling, Cost if wrong, and Wake condition, even when that finding
later resolves.

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
