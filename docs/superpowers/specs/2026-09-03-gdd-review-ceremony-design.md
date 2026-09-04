# GDD Review Ceremony Design

Route: Superpowers plan. Repositories: this repository
(`skills/gauntlet-driven-development/`) and the claude-config repository at
`~/.claude`.

## Goals

1. Each slice gets one task-scoped review and a capped fix loop directly after
   implementation. The four verification workers then run once each, fix
   inside their own remit, and never send work backwards.
2. A problem a worker cannot fix inside its remit gets an advisor decision
   (fix now, do not fix, or bring to the user). Every decision is recorded
   with its reason and its cost if wrong.
3. Feature closing runs one Branch Reviewer and one Security Reviewer,
   sequential and independent, followed by one combined fix dispatch and two
   scoped re-reviews. No second fix wave. No slice replay.
4. Security review belongs to the Security Reviewer at feature closing. The
   Branch Reviewer reports no security findings.

## Non-goals

- No concurrent claims in `gdd-workflow-state`.
- No migration of format-1 workspaces.
- No new agent file. The Task Reviewer and the re-reviewer are
  general-purpose dispatches with the Subagent-Driven Development templates.
- No readiness check for agent bodies and no deterministic tooling for them.
- No change to the Subagent-Driven Development skill.

## Terms

- Task Reviewer: a general-purpose subagent dispatched with
  `skills/subagent-driven-development/task-reviewer-prompt.md`.
- Re-reviewer: a general-purpose subagent dispatched with
  `skills/subagent-driven-development/re-review-prompt.md`.
- Workers: Cleaner, Architect, Hardener, QA (`e2e-runner`).
- Advisor: the Fable consultation. On Claude Code it is the built-in
  `advisor` tool, which reads the transcript and takes no arguments. On Codex
  it is the `$fable-advisor:advise` skill, which sends only the controller's
  last message. On both, the controller writes the full decision brief (the
  finding files, the case, the allowed decisions, the round count, and a
  request for the six ruling fields in D6) as its message immediately before
  the call.
- Slice round: one `fixer-max` dispatch plus its verification. Every slice
  holds one round counter with a cap of 5.

## Decisions

### D1: Slice ceremony order

`Implementer -> Task Reviewer -> Cleaner -> Architect -> Hardener -> QA ->
final suite -> verified`.

`compile_obligations` emits these rows per slice, in this order:

| Obligation | Type | Prerequisite | Results | Evidence |
| --- | --- | --- | --- | --- |
| `slice-N-implementer` | implementer | prior `slice-M-verified` | PASS, FAIL | implementer-report |
| `slice-N-review` | review | `slice-N-implementer` | PASS, FAIL | review-report |
| `slice-N-cleaner` | cleaner | `slice-N-review` | PASS, FAIL | cleaner-report |
| `slice-N-architect` | architect | `slice-N-cleaner` | PASS, FAIL | architect-report |
| `slice-N-hardener` | hardener | `slice-N-architect` | PASS, FAIL | hardener-report |
| `slice-N-qa` | qa | `slice-N-hardener` | PASS, FAIL | qa-report |
| `slice-N-final-suite` | final-suite | `slice-N-qa` | PASS, FAIL | final-suite-report |
| `slice-N-verified` | verified | `slice-N-final-suite` | PASS | verification-record |

`slice-N-security` no longer exists. The obligation-ID regex accepts `review`
and rejects `security` at slice scope.

`gdd-slice-state` states and transitions:

| From | Evidence | To |
| --- | --- | --- |
| `implementing` | Implementer report, `Status: DONE` or `DONE_WITH_CONCERNS` | `reviewing` |
| `reviewing` | `slice-N-review` accepted PASS | `verifying-cleaner` |
| `verifying-cleaner` | Cleaner report | `verifying-architect` |
| `verifying-architect` | Architect report | `verifying-hardener` |
| `verifying-hardener` | Hardener report, `Status: VERIFIED` | `verifying-qa` |
| `verifying-qa` | QA report, `Status: VERIFIED` | `verified` |

Fix rounds do not change the slice state. `verifying-security` is removed.
The Fixer-evidence entry into `verifying-cleaner` is removed.

### D2: Task Reviewer stage

The controller dispatches the Task Reviewer once per slice with the stock
template, unchanged, plus the `[gdd-finding-report]` addendum:

- Inputs: the brief from `scripts/task-brief`, the global constraints, the
  Implementer report path, and the package from
  `scripts/review-package PLAN_FILE BASE HEAD` for the slice range.
- Model: chosen per the Subagent-Driven Development Model Selection section,
  never below the Implementer's tier.
- Checklist: the stock checklist, including its security item.

Output: the stock report plus `Finding count: N` and one ten-field finding
file per Critical, Important, or Minor issue with `Origin role: Task Reviewer`
and `Severity claim:` equal to the stock severity. A ❌ spec-compliance item
is an Important finding unless the reviewer marks it Critical. The controller
checks each ⚠️ item against the cited code itself and records the result in
the review acceptance.

Acceptance: `slice-N-review` accepts PASS when no Critical or Important
finding is open, and FAIL otherwise. FAIL starts the fix rounds in D3. The
Task quality verdict is recorded as reported text and does not decide the
result.

### D3: Slice fix rounds

Scope: one open-findings list and one round counter per slice. Critical and
Important findings from the Task Reviewer, Critical and Important breakage
reported by any re-review, and every advisor `FIX_NOW` decision (D5) share
the same counter. The counter is the highest `Repair round` recorded on any
finding with scope `slice-N`.

One round:

1. One `fixer-max` dispatch with the complete open list, the brief, the
   Implementer report path (fix reports are appended), the fix base SHA, and
   the verification command. `fixer-max` is the executor for every round.
2. `scripts/review-package PLAN_FILE FIX_BASE HEAD` over the fix range.
3. One re-reviewer dispatch with the open list as `[FINDINGS]`, at a
   cheap-to-mid tier per Model Selection.

Verdicts: `ADDRESSED` resolves the finding. `NOT ADDRESSED` keeps it open.
Critical or Important breakage in the fix diff becomes a new finding with
`Origin role: Re-reviewer` on the open list. Minor breakage and Out-of-Scope
Observations become Minor findings and follow D7.

Ledger line per round:
`Slice <N>: fix round <R>/5 (<X> addressed, <Y> open; commits <a7>..<b7>)`.

Exit: when every listed finding is resolved, the controller accepts
`slice-N-review` PASS. When findings stay open after round 5, the controller
consults the advisor under case C3 (D5). A `NEEDS_CONTEXT` from `fixer-max`
is answered and redispatched inside the same round.

### D4: Worker remits

Each worker fixes inside its remit in place and forwards. It reports a
problem outside its remit under `## Observations` with `Finding count: N` and
ten-field finding files, `Origin role:` set to its role.

| Worker | Fixes in place | Reports as an observation |
| --- | --- | --- |
| Cleaner | Coverage, CRAP, DRY, mutation-site cleanup. Structure preserving. | Behavior defects, spec gaps |
| Architect | Boundaries, dependency direction, information hiding, architecture checks, property tests | Behavior defects, spec gaps |
| Hardener | Hardening tests, baseline failures, proven slice defects | Spec ambiguity (`NEEDS_SPEC_CLARIFICATION`), tooling |
| QA | QA-owned executable tests, verification metadata | Production defects (`REPAIR_REQUIRED`), spec ambiguity, tooling |

A Hardener production fix keeps the installed rule: commit, append evidence,
return `REVERIFY_REQUIRED`, and the controller dispatches a fresh Hardener
from the repaired commit. The controller records the fixed defect as a
finding with `Origin role: Hardener`, moves it to `REPAIRING` with
`Repair round` equal to the next slice round, and resolves it on the fresh
Hardener's `VERIFIED`. This counts one slice round.

`e2e-runner.md` changes:

- Line 78 becomes: on a violated scenario or QA observation, return
  `Status: REPAIR_REQUIRED` with a finding report. Do not repair production
  code. The controller consults the advisor. A fix is followed by a fresh QA.
- Line 80 becomes: return `Status: STALE_HARDENER` only when production or
  mutation inputs changed after the Hardener's verified commit with no
  controller-recorded `fixer-max` or Hardener fix event covering the change.
  The QA dispatch carries the recorded fix commits (short SHA and finding
  ID) made after the Hardener's verified commit. A recorded fix event after
  the Hardener is verified by QA alone. Its mutation evidence is not
  regenerated.
- `NEEDS_CONTEXT` and `NEEDS_TOOLING` from any worker are answered by the
  controller and redispatched. They do not reach the advisor.

### D5: Advisor routing

The controller consults the advisor in these cases:

| Case | Trigger | Allowed decisions |
| --- | --- | --- |
| C1 | A worker observation (D4) | `FIX_NOW`, `NO_FIX`, `ESCALATE` |
| C2 | Hardener or QA not `VERIFIED`: `REPAIR_REQUIRED`, `NEEDS_SPEC_CLARIFICATION` | `FIX_NOW`, `NO_FIX`, `ESCALATE` |
| C3 | Findings open after slice round 5 | `PARK`, `ESCALATE` |
| C4 | Residual findings after the feature-closing re-reviews (D8) | `NO_FIX`, `ESCALATE` |
| C5 | Any transition to `DISMISSED`, `PARKED`, or `BLOCKED`, or a repair that adds a dependency, subprocess, concurrency, persistence, credentials, an external side effect, a contract change, or new approved behavior | the transition, or `ESCALATE` |

Decision effects:

- `FIX_NOW`: one `fixer-max` dispatch with the finding before the next worker
  runs. Counts one slice round. The finding enters `REPAIRING` with
  `Replay through: downstream`. It resolves when the next worker obligation
  of its slice is accepted PASS. When QA reported it, a fresh QA is that
  worker. When the Hardener reported it, QA verifies it and mutation
  evidence is not regenerated (D4).
- `NO_FIX`: `DISMISSED` with the advisor's reason. Carried to feature closing.
- `PARK`: `PARKED` with the advisor's reason and wake condition. Carried to
  feature closing. The slice continues to the Cleaner.
- `ESCALATE`: `BLOCKED`. The controller finishes every other ready obligation
  and presents the finding with the ruling to the user. The user's ruling is
  recorded and applied as `FIX_NOW`, `NO_FIX`, or `PARK`.

Advisor input: the finding files, the slice brief, the reporting worker's
report, the slice state, and the current round count.

`downstream` order: `repair-start`, the `fixer-max` dispatch, the next
worker dispatched and accepted PASS, `repair-finish` `PASSED` with that
worker report as evidence, `RESOLVED`. The `guard` command permits the next
worker obligation of the slice to be claimed and accepted while a
`downstream` finding is `REPAIRING`. It still blocks every other obligation.

A C1 to C4 consultation satisfies C5 for the transition it decided. No
second consultation is made for that transition.

Cap rule: when the slice counter is 5, `FIX_NOW` and the Hardener rerun in
D4 are unavailable and the advisor is told so. C1 and C2 decisions are then
`NO_FIX`, `PARK`, or `ESCALATE`.

Advisor unavailable: `BLOCKED` on the boundary the ruling gates, finish every
other ready obligation, present to the user. Unchanged. `UNAVAILABLE` is
valid only after the built-in `advisor` tool errors on Claude Code, or the
`$fable-advisor:advise` skill reports its failure message on Codex.

### D6: Advisor consultation record

Every consultation writes one file and one ledger event
(`finding-GDD-F####-consult-K`, `K` from 1). The file holds these single-line
fields:

```text
Finding IDs:
Case:
Problem:
Verdict:
Recommendation:
Basis:
Risks and assumptions:
Flip condition:
Forward consult gates:
Decision:
Reason:
Cost if wrong:
Controller action:
```

`Verdict` through `Forward consult gates` are the advisor's ruling fields,
copied. The Codex skill returns them as fields. The Claude Code reply is not
schema-bound, so a field the ruling did not state is recorded as
`NOT GIVEN`. The controller fills `Decision`, `Reason`, `Cost if wrong`, and
`Controller action` on both harnesses. `Decision` is one of `FIX_NOW`, `NO_FIX`, `PARK`, `ESCALATE`, or
`USER:<ruling>`. `Fable result:` on a terminal disposition points to this
file. The digest lists every consultation. The completion report repeats
each one as
`Advisor consultation <K>: <finding IDs>; <case>; <decision>; <reason>; cost if wrong: <cost>`.
Both feature-closing briefs carry every consultation.

### D7: Dispositions

| Source | Severity | Disposition |
| --- | --- | --- |
| Task Reviewer, re-review breakage | Critical, Important | `REPAIRING` in the slice rounds |
| Task Reviewer, re-review breakage, Out-of-Scope Observations | Minor | `DEFERRED` to feature closing |
| Worker observation | any | Advisor C1: `REPAIRING`, `DISMISSED`, or `BLOCKED`. `PARKED` only at the cap. Never `DEFERRED` |
| Open after round 5 | any | Advisor C3: `PARKED` or `BLOCKED` |
| Branch Reviewer, Security Reviewer | any | `REPAIRING` in the closing fix dispatch |
| Residual after the closing re-reviews | any | Advisor C4: `DISMISSED` or `BLOCKED` |

Finding states and their transitions are unchanged.

### D8: Feature closing

Feature obligations:

| Obligation | Type | Prerequisite | Results | Evidence |
| --- | --- | --- | --- | --- |
| `feature-branch-review` | branch-review | every `slice-N-verified` | PASS, FAIL | branch-review-report |
| `feature-security-review` | security-review | every `slice-N-verified` | PASS, FAIL | security-review-report |
| `feature-findings-digest` | findings-digest | both reviews | PASS | findings-digest |
| `feature-complete` | complete | `feature-findings-digest` | PASS | completion-evidence |

Both reviews become ready together. The engine holds one claim at a time and
`selected_ready_obligation` takes the first READY row, so the Branch Reviewer
runs first and the Security Reviewer second.

1. Branch Reviewer: the package for the plan base to HEAD, the spec and plan
   sources, and a brief carrying every `DEFERRED`, `DISMISSED`, and `PARKED`
   finding with its ruling, cost if wrong, and wake condition, plus every
   consultation (D6). Accept PASS or FAIL. Findings: scope `feature`,
   `Origin role: Branch Reviewer`.
2. Security Reviewer: the same package and brief. It does not receive the
   Branch Reviewer's report. Accept PASS or FAIL. Findings: scope `feature`,
   `Origin role: Security Reviewer`.
3. When either review reports findings: one `fixer-max` dispatch with the
   combined list, all severities, both origins. Each finding enters
   `REPAIRING` with `Repair round: 1`, `Executor: fixer-max`,
   `Replay through: re-review`. Repair acceptance invalidates both review
   obligations through the existing `EvidenceInvalidated` path.
4. Two scoped re-reviews over the fix range from
   `scripts/review-package PLAN_FILE FIX_BASE HEAD`: a fresh Branch Reviewer
   with the Branch Reviewer findings, then a fresh Security Reviewer with the
   Security Reviewer findings. Each is dispatched with its agent's stock body
   and a scope instruction: verdict each listed finding `ADDRESSED` or
   `NOT ADDRESSED`, inspect the fix diff for new breakage, do not re-review
   untouched code. Each report re-accepts its obligation PASS when every
   listed finding is `ADDRESSED` and the fix diff has no Critical or Important
   breakage, and FAIL otherwise.
5. Residual findings (`NOT ADDRESSED`, or new breakage) go to the advisor
   under C4. When every residual is `DISMISSED`, the obligation accepts PASS
   with the re-review report and the consultation files as evidence.
   `BLOCKED` residuals stop at the user.
6. No second fix dispatch, no slice replay, no fresh whole-branch review.
   `feature-findings-digest` and `feature-complete` follow.

`Final wave findings`, `Affected slices`, affected-slice replay,
`replay-entry`, and `final_wave_pending` are removed from the engine.

### D9: Security Reviewer

`~/.claude/agents/security-reviewer.md` keeps its frontmatter name and tool
list. Changes:

- Description: read-only whole-branch security reviewer dispatched once at
  feature closing after every slice is verified, and once more as a scoped
  re-review after the closing fix dispatch.
- Dispatch inputs: the D8 step 2 list, or the D8 step 4 scoped list. Missing
  inputs return `NEEDS_CONTEXT` naming them.
- The review method (authz obligations first, per-handler AUTHZ CHECK, lens
  scan, test discrimination, backward trace) is unchanged and runs over the
  whole branch diff.
- The sentence "Only `Status: CLEAN` hands the slice to the Hardener. Findings
  route to a fixer, then scoped Cleaner and Architect reruns, followed by a
  fresh Security Reviewer." becomes: findings are recorded with scope
  `feature` and join the closing fix dispatch. A fresh Security Reviewer
  re-reviews the fix range.
- Model pin: fable at high effort. `guard-dispatch-model.sh` case
  `security-reviewer` changes from `*opus*` to `*fable*`.

`codex-agents/security-reviewer.toml`: regenerated from the new body with the
new description, `model_reasoning_effort = "xhigh"`, the same `gpt-5.6-sol`
model, the new body SHA-256, and the byte-for-byte body after
`SOURCE_BODY_BEGIN`. The Codex adaptation line "Review only the dispatched
slice" becomes "Review only the dispatched branch diff".

Finding rules: `Origin role: Security Reviewer` and `Origin role: Branch
Reviewer` are valid only at scope `feature`. `Origin role: Task Reviewer`,
`Re-reviewer`, `Cleaner`, `Architect`, `Hardener`, and `QA` are valid only at
slice scope.

### D10: Branch Reviewer and related bodies

`~/.claude/agents/branch-reviewer.md`:

- The description drops "and emergent security risks".
- The opening paragraph drops "and security risks created by the slices in
  combination".
- Method step 7, "Emergent security pass", is deleted. Remaining steps keep
  their order.
- One sentence under Method: security review belongs to the Security
  Reviewer. The Branch Reviewer does not report or suggest security findings.
- The brief section names the D8 step 1 inputs and the scoped re-review mode.

`~/.claude/agents/architect.md`: the three handoff sentences that name the
Security Reviewer name the Hardener.

`~/.claude/agents/e2e-runner.md`: D4, and its dispatch-input list gains the
recorded fix commits after the Hardener's verified commit.

`~/.claude/agents/hardener.md`: unchanged.

`~/.claude/agents/fixer-max.md`: unchanged. The slice-round brief and the
closing brief use its existing contract (verdict file, findings, verification
command).

Codex TOMLs for `branch-reviewer`, `architect`, and `e2e-runner` are
regenerated with new body SHA-256 values. The parity test
`superpowers-bridge/scripts/agent-source-parity.test.sh` asserts the Architect
handoff sentence names the Hardener and the Codex Security Reviewer runs at
xhigh.

### D11: `gdd-workflow-state`

- `compile_obligations`: D1 and D8 rows.
- Obligation-ID regex: slice types `implementer review cleaner architect
  hardener qa final-suite verified`. Feature IDs add
  `feature-security-review`. Finding obligations become
  `finding-GDD-F####-{supplement,dispose,wake,resolve,repair-start-[1-5],repair-finish-[1-5],repair-result,consult-[1-9],digest}`.
- Reducer: the `final_wave_pending` case, `replay_is_complete`,
  `final_wave_is_registered`, `role_rank`, and the affected-slice
  invalidation branch are removed. A `REPAIRING` finding with
  `Replay through: re-review` completes on an accepted `repair-finish` whose
  evidence is a re-review report. A `REPAIRING` finding with
  `Replay through: downstream` completes when the next worker obligation of
  its slice is accepted PASS.
- `finding_origin_for_obligation`: `review` maps to `Task Reviewer`,
  `feature-branch-review` to `Branch Reviewer`, `feature-security-review` to
  `Security Reviewer`. The `security` case is removed.
- `validate_format_version` accepts `2` only. Initialization writes `2`.
  A format-1 workspace fails with "workflow format version is unknown: 1".
- `print_status` and the adapters' `Active claim:` parsing are unchanged.

### D12: `gdd-slice-state`

- States: D1 table. `verifying-security` and its accept-active case are
  removed. `reviewing` is added with its two transitions.
- `require_status` and `require_status_one_of` are unchanged.

### D13: `gdd-finding-state`

- Origins: `Task Reviewer`, `Re-reviewer`, `Cleaner`, `Architect`,
  `Hardener`, `QA`, `Branch Reviewer`, `Security Reviewer`, with the D9
  scope rule.
- `Replay through` accepts `re-review` or `downstream` only. The origin-rank
  validation and `Affected slices` are removed.
- `repair-start`: `Executor: fixer-max` for every round. `Repair round` is
  1 through 5, strictly greater than the finding's previous round, and not
  lower than any round already recorded on the same slice. A slice-scoped
  round above 5 fails with "slice round cap reached".
- `repair-finish`: `PASSED` evidence is the re-review report for
  `re-review`, or the accepted downstream worker report for `downstream`.
- `guard`: permits the next worker obligation of a slice while a
  `downstream` finding of that slice is `REPAIRING` (D5 order).
- New command `consult FINDING_ID CONSULT_FILE`: validates the D6 fields and
  records `finding-GDD-F####-consult-K`.
- `repair-entry` and `validate_final_wave_findings` are removed.
- `digest` prints every consultation after the findings.

### D14: `finding-policy.md`, Policy-Version 2

Section headings are unchanged. Bodies change as follows:

- Authority: the advisor decides the D5 cases. Approved OpenSpec artifacts and
  explicit user decisions remain binding. The advisor does not change a
  role's technical verdict.
- Repair: open Critical or Important slice findings enter the slice rounds
  and hold `slice-N-review` at FAIL until resolved. Every round uses a fresh `fixer-max`. A round is verified by a
  scoped re-review, or by the downstream workers for a `FIX_NOW` fix. The
  cap is five rounds per slice. The controller does not edit the
  implementation itself.
- Fable: the D5 table, the D5 decision effects, and the D6 record.
- Role gates: the sentence "Adjudication may route a Security or Branch
  Review finding without changing the role's technical verdict" is unchanged.
  "Fixer and Fixer Max receive only findings in `REPAIRING`" becomes "Fixer
  Max receives only findings in `REPAIRING`".
- Feature closing: D8.

`gdd-readiness`: `EXPECTED_POLICY_VERSION='Policy-Version: 2'` and format
version `2`. `policy_headings` is unchanged.

### D15: `SKILL.md`

- Slice ceremony: the D1 order, the D2 dispatch, and the D3 rounds.
- "Findings and replay" becomes "Findings and fix rounds": D3, D4, D5, D7.
- Per-finding execution record: `Replay through` values `re-review` or
  `downstream`. `Affected slices` is removed. An "Advisor consultation
  record" subsection lists the D6 fields.
- "Ordered slice-repair execution record" becomes "Slice fix round record":
  the D3 round steps and ledger line.
- Feature closing and "Final-wave dispatch order" become "Feature closing
  dispatch order": the D8 steps.
- Completion record: every consultation in the D6 line format.
- Fable invocation: every `fable-advisor:advise` mention becomes the
  per-harness invocation in Terms, and the `UNAVAILABLE` rule names the
  per-harness failure in D5.
- Rationalizations: the two Security-stage rows are deleted. Rows are added
  for "one more replay will fix it" (there is no replay), "the worker can
  fix it while it is there" (outside its remit it reports), and "the advisor
  said fix it, no record needed" (every consultation is recorded).
- The addendum role list names `Task Reviewer` and drops `Security Reviewer`
  at slice scope.

### D16: Versions

`format-version` 2 with no migration. `Policy-Version: 2`.

## Data flow

1. `slice-N-implementer` accepted. Slice state `reviewing`.
2. Task Reviewer dispatched. Findings recorded. PASS closes the stage.
   FAIL runs slice rounds until resolved or the cap.
3. Cleaner, Architect, Hardener, QA run once each. Observations go to the
   advisor. `FIX_NOW` fixes run before the next worker.
4. `slice-N-final-suite`, `slice-N-verified`.
5. After the last slice: Branch Reviewer, Security Reviewer, one combined
   `fixer-max` dispatch, two scoped re-reviews, residuals to the advisor.
6. Digest, complete.

## File map

claude-config repository:

- `agents/security-reviewer.md`: D9.
- `agents/branch-reviewer.md`, `agents/architect.md`, `agents/e2e-runner.md`:
  D10 and D4.
- `codex-agents/security-reviewer.toml`, `codex-agents/branch-reviewer.toml`,
  `codex-agents/architect.toml`, `codex-agents/e2e-runner.toml`: regenerated.
- `superpowers-bridge/scripts/agent-source-parity.test.sh`: D10 assertions.
- `hooks/guard-dispatch-model.sh`: D9 pin.

This repository, `skills/gauntlet-driven-development/`:

- `SKILL.md`: D15.
- `finding-policy.md`: D14.
- `scripts/gdd-workflow-state`: D11.
- `scripts/gdd-slice-state`: D12.
- `scripts/gdd-finding-state`: D13.
- `scripts/gdd-readiness`: D14.
- `scripts/gdd-workflow-state.test.sh`, `scripts/gdd-slice-state.test.sh`,
  `scripts/gdd-finding-state.test.sh`: fixtures for `slice-N-review`,
  `reviewing`, `feature-security-review`, `consult-K`, the slice round cap,
  the `fixer-max` executor rule, the two `Replay through` values, and format
  version 2. Every `slice-1-security`, `verifying-security`,
  `Affected slices`, `Final wave findings`, and `replay-entry` fixture is
  removed.
- `tests/openspec-gdd/test-gdd-readiness.sh`: `Policy-Version: 2` and format
  version 2.

## Error handling

- A reviewer or worker returns `NEEDS_CONTEXT` or `NEEDS_TOOLING`: the
  controller supplies the input and redispatches.
- A `repair-start` with `Executor: fixer` fails.
- A slice-scoped `repair-start` above round 5 fails.
- A feature-scoped finding with a slice-only origin, or a slice-scoped
  finding with a feature-only origin, fails validation.
- A consultation file with a missing field fails `consult`.
- A format-1 workspace fails with the unknown-version message.
- Advisor unavailable: `BLOCKED`, finish other ready obligations, present to
  the user.

## Risks

- Mutation evidence is not regenerated for a production fix made after the
  Hardener. The Hardener gate is untrue for that fix range. QA, the Branch
  Reviewer, and the Security Reviewer are the remaining checks on it.
- A `FIX_NOW` fix consumes a slice round. A slice with several worker
  observations can reach the cap before the Task Reviewer's own findings
  are resolved.
- Each closing reviewer reads the whole branch diff in one context. A long
  branch may exceed what one review can hold.
- Both closing reviewers may report the same defect. Adjudication records it
  once under the origin that reported it first.

## Verification

- Script tests pass with the D1 and D8 obligation rows, the `reviewing`
  state, one claim at a time, `feature-security-review` after
  `feature-branch-review`, invalidation of both on repair acceptance, and a
  digest that stays `PENDING` until both reviews hold PASS.
- `gdd-finding-state` rejects `Executor: fixer`, rejects a slice round above
  5, rejects an origin at the wrong scope, accepts `consult`, and prints
  consultations in the digest.
- `gdd-readiness` fails on `Policy-Version: 1` and on format version 1.
- `scripts/install-codex-agents.test.sh` and
  `superpowers-bridge/scripts/agent-source-parity.test.sh` pass with the four
  regenerated TOMLs.
- The hook denies an opus override for `security-reviewer` and allows fable.
- One manual run in Claude Code and one in Codex of a slice with a Task
  Reviewer FAIL, one fix round, one worker observation, and a feature closing
  with one finding, each producing the ledger lines, the consultation
  records, and the completion report lines defined here.
