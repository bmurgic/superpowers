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
3. Verify the report and non-empty commit range. Do not accept self-reported completion. Mark each proven coarse implementation task `[x]`, then run `scripts/gdd-slice-state PLAN_FILE N reviewing IMPLEMENTER_REPORT`. The report must carry `Status: DONE` or `Status: DONE_WITH_CONCERNS`.
4. Dispatch the Task Reviewer with the stock `skills/subagent-driven-development/task-reviewer-prompt.md` template, unchanged, plus the `[gdd-finding-report]` addendum. Give it the brief, the global constraints, the Implementer report path, and the package from `scripts/review-package PLAN_FILE BASE HEAD` for the slice range. Choose its model per the Subagent-Driven Development Model Selection section, never below the Implementer's tier. It writes `Finding count: N` and one finding file per Critical, Important, or Minor issue with `Origin role: Task Reviewer`. A ❌ spec-compliance item is Important unless the reviewer marks it Critical. Check each ⚠️ item against the cited code and record the result in the review acceptance. Accept the review with `scripts/gdd-finding-state PLAN_FILE report N 'Task Reviewer' REVIEW_REPORT FINDINGS_DIR`. It records PASS when no Critical or Important finding is open and FAIL otherwise. FAIL starts the slice fix rounds below. After PASS, run `scripts/gdd-slice-state PLAN_FILE N verifying-cleaner REVIEW_REPORT FINDINGS_DIR`.
5. Run one agent at a time in this exact order: `cleaner -> architect -> hardener -> e2e-runner [gdd-gate: slice-qa]`. Before each dispatch after Cleaner, advance the state with the prior role's evidence and that role's `FINDINGS_DIR`: `verifying-architect`, `verifying-hardener`, then `verifying-qa`. Pass the QA `FINDINGS_DIR` with its final-suite evidence to `verified` so QA, its findings, the final suite, and verification remain one transaction. Each worker fixes inside its remit in place and reports anything outside it under `## Observations` as findings with its own `Origin role`. A worker observation goes to the advisor under case C1 before the next worker is dispatched.
6. Every lifecycle role receives the slice brief, exact behavior and QA references, current revision, prior verdict or commit, report path, applicable commands, and this exact addendum. Do not add it to Fixer Max, which receives only findings already in `REPAIRING`.

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

This contract applies to the Task Reviewer, Re-reviewer, Cleaner, Architect,
Hardener, QA, Branch Reviewer, and Security Reviewer. Role status is evidence, not routing authority. Hardener
and QA verification statuses remain binding for their own gates.
The role adapter rejects a count that does not match the files, a duplicate
number, an unexpected file, or an origin that differs from the claimed role.
It accepts the role result and all `FindingReported` events in one transaction,
so the role boundary cannot advance between them.
7. After QA reports `VERIFIED` against the current Hardener-approved revision, capture the passing final slice suite as a non-empty evidence file containing `Status: PASS`. Run `scripts/gdd-slice-state PLAN_FILE N verified QA_REPORT FINAL_SUITE_REPORT FINDINGS_DIR`; this atomically changes the slice state to `[x] VERIFIED` and checks only `N.V`. The QA result, its findings, the final suite, and verification are one transaction. The next Implementer receives `[gdd-gate: prior-slice-verified]`.

## Findings and fix rounds

A slice has one review, bounded fix rounds, and one first pass per worker. Nothing is replayed.

For every lifecycle finding, the controller:

1. Reads the complete role report without reacting.
2. Restates each finding as one falsifiable technical claim.
3. Accepts the role result through its grouped lifecycle adapter. That adapter assigns Finding IDs, derives the role scope, validates the complete numbered files, and appends every `FindingReported` event with the role result before changing the slice boundary. Use the current slice number for slice roles and `feature` for Branch Reviewer and Security Reviewer.
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

Consult the advisor in the cases the policy snapshot lists, C1 through C5. On
Claude Code, call the built-in `advisor` tool, which reads the transcript and
takes no arguments. On Codex, invoke the `$fable-advisor:advise` skill, which
sends only your last message. On both, write the full decision brief as your
message immediately before the call: the finding files, the case, the allowed
decisions, the round count, and a request for the ruling fields Verdict,
Recommendation, Basis, Risks and assumptions, Flip condition, and Forward
consult gates. Claim `finding-<ID>-consult-K` and record the result with
`scripts/gdd-finding-state PLAN_FILE consult FINDING_ID CONSULT_FILE` before
acting on it. Record an unavailable consultation exactly as `Fable result:
UNAVAILABLE: <reason>`. The advisor decides the C1 through C5 cases. Approved
artifacts and explicit user decisions remain authoritative.

### Completion record

Complete every finding scenario as an execution record, not a proposed workflow.
Append each record at the execution point for its command, result, or dispatch.
Do not reconstruct the sequence after later work finishes.
Preserve the originating role's `Technical verdict:`, `Severity claim:`, and
`Blocking claim:` as evidence while the controller chooses the disposition.

Repeat every consultation as
`Advisor consultation <K>: <finding IDs>; <case>; <decision>; <reason>; cost if wrong: <cost>`.

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
conditions that excluded every gate. `Fable result:` points to the
consultation record file. `UNAVAILABLE` is valid only after the built-in
`advisor` tool errors on Claude Code, or the `$fable-advisor:advise` skill
returns `Fable Advisor failed: <exact failure>. No advisory ruling was
produced.` on Codex. A `REPAIRING` disposition names `Replay through:
re-review` or `Replay through: downstream`. There is no `Affected slices`
field.
Prompt constraints, test fixtures, and lack of shell execution do not prove unavailability.

### Advisor consultation record

Every consultation writes one file and claims `finding-<ID>-consult-K`, `K`
from 1. The file holds these single-line fields in this order, each exactly
once:

```text
Finding IDs: <comma-separated finding IDs>
Case: <C1, C2, C3, C4, or C5>
Problem: <what was asked>
Verdict: <advisor>
Recommendation: <advisor>
Basis: <advisor>
Risks and assumptions: <advisor>
Flip condition: <advisor>
Forward consult gates: <advisor>
Decision: <FIX_NOW, NO_FIX, PARK, ESCALATE, or USER:<ruling>>
Reason: <controller>
Cost if wrong: <controller>
Controller action: <controller>
```

Copy `Verdict` through `Forward consult gates` from the ruling. Write
`NOT GIVEN` for a field the Claude Code reply did not state. Record the file
with `scripts/gdd-finding-state PLAN_FILE consult FINDING_ID CONSULT_FILE`.
The digest and the completion report list every consultation.

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
   Reviewer or Security Reviewer finding. Continue every other ready obligation, then stop at
   `USER_AUTHORITY_REQUIRED` and present the finding to your human partner.
   Their ruling returns the finding to `REPORTED` with a `Wake evidence:`
   artifact. Record the later disposition with `User authority: <file>` holding
   that ruling when Fable is still unavailable. For a repair with no
   Fable gate, record `Fable gate: NOT REQUIRED: <checked conditions>`.
2. Use the slice fix round record below for slice findings and the feature
   closing dispatch order for feature findings.
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

### Slice fix round record

One open-findings list and one round counter per slice. Critical and Important
findings from the Task Reviewer, Critical and Important breakage reported by
any re-review, and every advisor `FIX_NOW` decision share the counter. The
counter is the highest `Repair round` recorded on any finding with scope
`slice-N`. The cap is 5. Never dispatch round 6.

For each open finding, transition it with `scripts/gdd-finding-state PLAN_FILE transition FINDING_ID REPAIRING EVIDENCE_FILE`
carrying `Repair hypothesis`, `Repair base` (the revision before the first fix
commit), and `Replay through: re-review`. Then append these entries at their
execution points in exactly this order:

1. `repair-start`: for each finding in the round, claim
   `finding-<ID>-repair-start-R` and run `scripts/gdd-finding-state PLAN_FILE repair-start FINDING_ID EVIDENCE_FILE`
   with `Repair round: R`, `Executor: fixer-max`, a fresh `Agent ID`, and the
   hypothesis. R is the next slice round. A round after the first needs the
   prior `repair-finish` to be `FAILED` and new evidence or a different
   falsifiable hypothesis.
2. `Issued fixer-max dispatch:` one dispatch with the complete open list, the
   brief, the Implementer report path (fix reports are appended), the fix base
   SHA, and the verification command. Answer a `NEEDS_CONTEXT` and redispatch
   inside the same round.
3. `repair-result`: for each finding, claim `finding-<ID>-repair-result-R`
   and run `scripts/gdd-finding-state PLAN_FILE repair-result FINDING_ID FIXER_REPORT`.
   This frees `slice-N-review` for the re-review.
4. `Re-review:` run `scripts/review-package PLAN_FILE FIX_BASE HEAD`, then
   dispatch one Re-reviewer with
   `skills/subagent-driven-development/re-review-prompt.md`, the open list as
   `[FINDINGS]`, the package, and the `[gdd-finding-report]` addendum, at a
   cheap-to-mid tier per Model Selection. Claim `slice-N-review` and accept
   its report with `scripts/gdd-finding-state PLAN_FILE report N Re-reviewer REVIEW_REPORT FINDINGS_DIR`.
   `ADDRESSED` resolves a finding. `NOT ADDRESSED` keeps it open. Critical or
   Important breakage in the fix diff is a new finding with
   `Origin role: Re-reviewer` on the open list. Minor breakage and
   Out-of-Scope Observations are Minor findings and are `DEFERRED`.
5. `repair-finish`: for each finding, claim `finding-<ID>-repair-finish-R`
   and run `scripts/gdd-finding-state PLAN_FILE repair-finish FINDING_ID EVIDENCE_FILE`
   with `Repair head`, `Replay status: VERIFIED` for `ADDRESSED` or `FAILED`
   for `NOT ADDRESSED`, and the re-review report as `Replay evidence`.
6. `RESOLVED`: for each verified finding, claim `finding-<ID>-resolve` and
   record the explicit `REPAIRING -> RESOLVED` transition.
7. Ledger line: `Slice <N>: fix round <R>/5 (<X> addressed, <Y> open; commits <a7>..<b7>)`.

When every listed finding is resolved, claim `slice-N-review` and accept PASS
through `report N Re-reviewer` with the re-review report and an empty findings
directory. Then run `scripts/gdd-slice-state PLAN_FILE N verifying-cleaner REVIEW_REPORT FINDINGS_DIR`.
When findings stay open after round 5, consult the advisor under case C3.

### Downstream fix record

An advisor `FIX_NOW` on a worker observation, or a Hardener
`REVERIFY_REQUIRED`, uses the same round counter with
`Replay through: downstream`. Record in this order: `repair-start`
(`Executor: fixer-max`), the dispatch, `repair-result`, the next worker of the slice
dispatched and accepted PASS, `repair-finish` with `Replay status: VERIFIED`
and that worker's report as `Replay evidence`, then `RESOLVED`.
`scripts/gdd-finding-state PLAN_FILE guard N TARGET_STATE` permits only that
next worker while the finding is `REPAIRING`. When QA reported the finding, a
fresh QA is the next worker. When the Hardener reported it, QA verifies it and
mutation evidence is not regenerated.

Before each later dispatch, check wake conditions for findings that touch the
same code, interface, task dependency, or changed premise. Include each
matching Finding ID, Ruling, Cost if wrong, and Wake condition in the dispatch.
Return a woken finding to `REPORTED` with a `Wake evidence:` artifact before
dependent work starts.

Keep bounded escalation and ledger entries from the approved plan.

## Feature closing

After every slice is verified, `feature-branch-review` and
`feature-security-review` become ready together. The engine holds one claim at
a time, so the Branch Reviewer runs first and the Security Reviewer second.
Both briefs carry the package for the plan base to HEAD, the spec and plan
sources, every `DEFERRED`, `DISMISSED`, and `PARKED` finding with its Finding
ID, Ruling, Cost if wrong, and Wake condition, and every consultation record.
The Security Reviewer does not receive the Branch Reviewer's report.

### Feature closing dispatch order

Record the closing execution boundary in this order:

1. `Branch Reviewer:` dispatch and outcome. Accept with
   `scripts/gdd-finding-state PLAN_FILE report feature 'Branch Reviewer' REPORT FINDINGS_DIR`.
   Any finding records FAIL.
2. `Security Reviewer:` dispatch and outcome. Accept with
   `scripts/gdd-finding-state PLAN_FILE report feature 'Security Reviewer' REPORT FINDINGS_DIR`.
   Any finding records FAIL.
3. `REPAIRING:` when either review reported findings, transition each with
   `Repair base` and `Replay through: re-review`, then `repair-start` each
   with `Repair round: 1`, `Executor: fixer-max`, and one shared fresh
   `Agent ID`. Feature closing allows one round.
4. `Issued combined fixer-max dispatch:` one dispatch with the combined list,
   all severities, both origins. Record `repair-result` for each finding with
   the fixer report. Repair acceptance invalidates both review obligations.
5. `Scoped re-reviews:` `scripts/review-package PLAN_FILE FIX_BASE HEAD`, then
   a fresh Branch Reviewer with the Branch Reviewer findings, then a fresh
   Security Reviewer with the Security Reviewer findings. Each receives its
   stock body and this scope instruction: verdict each listed finding
   `ADDRESSED` or `NOT ADDRESSED`, inspect the fix diff for new breakage, do
   not re-review untouched code. Accept each report through
   `report feature <origin>`. It re-accepts PASS when every listed finding is
   resolved and the fix diff has no new finding, and FAIL otherwise.
6. `repair-finish` and `RESOLVED:` for each `ADDRESSED` finding, record
   `Replay status: VERIFIED` with its re-review report as evidence, then
   `REPAIRING -> RESOLVED`. `NOT ADDRESSED` records `Replay status: FAILED`.
7. `Residuals:` `NOT ADDRESSED` findings and new breakage go to the advisor
   under case C4. When every residual is `DISMISSED`, claim the review and
   accept PASS with the re-review report and the consultation files as
   evidence. `BLOCKED` residuals stop at the user.
8. No second fix dispatch, no slice replay, no fresh whole-branch review.
   `feature-findings-digest` and `feature-complete` follow.

Claim the digest obligation, then run `scripts/gdd-workflow-state PLAN_FILE digest OUTPUT_FILE`.
It reads reduced state and writes every unchanged deferred, dismissed, and
parked finding with its Finding ID, origin, ruling, cost if wrong, wake
condition, and evidence digest, plus every consultation under
`## Advisor consultations`. It accepts `FindingsDigestWritten` through the
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

## Stop conditions

Stop and escalate before dispatch when the OpenSpec plan, task brief, behavior reference, QA procedure, required current revision, or exact repair range is unavailable.
Do not mark a slice `[x]`, start a dependent Implementer, reuse stale QA, or skip a lifecycle role because of deadline, prior approval, passing focused tests, or user pressure.
Do not continue on a non-empty range without report evidence.

## Rationalizations

| Shortcut                                                 | Required response                                                                                   |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| "Review roles can catch up later."                       | Keep the next slice blocked until the ordered ceremony verifies the current slice.                 |
| "The Architect approved before the fix."                 | A fix after a worker's PASS is a downstream finding. The next worker verifies it. A prior verdict is not coverage. |
| "QA already passed."                                     | A production fix after QA requires one fresh full-slice QA pass.                                    |
| "The browser is unavailable, but acceptance tests pass." | QA cannot report `VERIFIED`. Keep the slice and next Implementer blocked.                           |
| "One more replay will fix it."                           | There is no replay. An open finding takes a numbered fix round with a fresh fixer-max, capped at 5. |
| "The worker can fix it while it is there."               | A worker fixes only inside its remit. Everything else is an observation the advisor routes.        |
| "The advisor said fix it, no record needed."             | Every consultation is recorded with `consult` before the controller acts on it.                    |

## Red flags

- Marking the `N.V` verification gate `[x]` from an Implementer report.
- Editing a `Slice state` line or `N.V` gate without `gdd-slice-state`.
- Starting a dependent slice before `[gdd-gate: prior-slice-verified]`.
- Treating a pre-fix verdict as coverage of the repair delta.
- Giving the Re-reviewer the whole slice instead of the fix range.
- Dispatching a fixer-max without `repair-start`, or acting on an advisor ruling without a consultation record.
- Starting round 6, or a second feature closing fix dispatch.

These mean the slice is still open.
