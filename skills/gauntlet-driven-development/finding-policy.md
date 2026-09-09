# GDD finding policy

Policy-Version: 2

## Authority

Lifecycle roles report technical findings and verification verdicts. The GDD
controller verifies each finding and chooses its workflow disposition. The
advisor decides the consultation cases listed under Astra. The approved
OpenSpec artifacts and explicit user decisions are binding. The advisor does
not change a role's technical verdict.

## Finding report

Every finding report contains these single-line fields:

- `Origin role:`
- `Severity claim:`
- `Blocking claim:`
- `Observed failure:`
- `Evidence:`
- `Violated authority:`
- `Assumptions:`
- `Failure scenario:`
- `Proposed repair:`
- `Repair effects:`

The controller assigns the finding ID. Missing information keeps the finding
`REPORTED` until the controller verifies the field or records why it does not
apply.

## Finding states

Allowed states are `REPORTED`, `REPAIRING`, `RESOLVED`, `DEFERRED`, `DISMISSED`,
`PARKED`, and `BLOCKED`. The only allowed transitions are:

```text
REPORTED -> REPAIRING -> RESOLVED
REPORTED -> DEFERRED | DISMISSED | PARKED | BLOCKED
REPAIRING -> DEFERRED | DISMISSED | PARKED | BLOCKED
DEFERRED | DISMISSED | PARKED -> REPORTED
BLOCKED -> REPORTED
```

`REPORTED` and `BLOCKED` stop lifecycle advancement. `REPAIRING` holds the
owning review at FAIL for a `Replay through: re-review` finding, and permits
only the next worker of its slice for a `Replay through: downstream` finding.
`RESOLVED`, `DEFERRED`, `DISMISSED`, and `PARKED` permit later lifecycle work
after their required evidence passes validation.

## Adjudication

For each finding, the controller restates the claim, checks the cited evidence,
compares it with the approved artifacts, tests its assumptions and threat
premises, checks the proposed repair's effects, and records the disposition,
reason, and cost if wrong. The controller does not pre-judge reviewer output or
tell a role which findings to suppress.

## Repair

Open Critical or Important slice findings enter the slice fix rounds and hold
`slice-N-review` at FAIL until they resolve. Every round uses a fresh
`fixer-max`. A round is verified by a scoped re-review, or by the downstream
workers for a `FIX_NOW` fix. The cap is five rounds per slice and one round at
feature closing. Every later round needs new evidence or a different
falsifiable hypothesis. The controller does not edit the implementation
itself.

## Astra

The controller consults the advisor in these cases:

| Case | Trigger | Allowed decisions |
| --- | --- | --- |
| C1 | A worker observation | `FIX_NOW`, `NO_FIX`, `ESCALATE` |
| C2 | Hardener or QA not `VERIFIED`: `REPAIR_REQUIRED`, `NEEDS_SPEC_CLARIFICATION` | `FIX_NOW`, `NO_FIX`, `ESCALATE` |
| C3 | Findings open after slice round 5 | `PARK`, `ESCALATE` |
| C4 | Residual findings after the feature-closing re-reviews | `NO_FIX`, `ESCALATE` |
| C5 | Any transition to `DISMISSED`, `PARKED`, or `BLOCKED`, or a repair that adds a dependency, subprocess, concurrency, persistence, credentials, an external side effect, a contract change, or new approved behavior | the transition, or `ESCALATE` |

Decision effects:

- `FIX_NOW`: one `fixer-max` dispatch with the finding before the next worker
  runs. Counts one slice round. The finding enters `REPAIRING` with
  `Replay through: downstream` and resolves when the next worker obligation
  of its slice is accepted PASS. When QA reported it, a fresh QA is that
  worker. When the Hardener reported it, QA verifies it and mutation evidence
  is not regenerated.
- `NO_FIX`: `DISMISSED` with the advisor's reason. Carried to feature closing.
- `PARK`: `PARKED` with the advisor's reason and wake condition. Carried to
  feature closing. The slice continues to the Cleaner.
- `ESCALATE`: `BLOCKED`. The controller finishes every other ready obligation
  and presents the finding with the ruling to the user. The user's ruling is
  recorded and applied as `FIX_NOW`, `NO_FIX`, or `PARK`.

A C1 to C4 consultation satisfies C5 for the transition it decided. When the
slice counter is 5, `FIX_NOW` is unavailable and the advisor is told so.

Every consultation writes one record with these single-line fields, each
exactly once: `Finding IDs`, `Case`, `Problem`, `Verdict`, `Recommendation`,
`Basis`, `Risks and assumptions`, `Flip condition`, `Forward consult gates`,
`Decision`, `Reason`, `Cost if wrong`, `Controller action`. `Verdict` through
`Forward consult gates` are the advisor's ruling fields, copied. A field the
ruling did not state is `NOT GIVEN`. `Decision` is `FIX_NOW`, `NO_FIX`,
`PARK`, `ESCALATE`, or `USER:<ruling>`. `Astra result:` on a terminal
disposition points to this record.

If the advisor is unavailable, block the finding on the boundary its ruling
gates, finish every other ready obligation, then present the finding to the
user. A later disposition of that finding without the advisor requires a
recorded user ruling.

## Interruption

Interrupt the user for a finding only when an accepted requirement needs new
behavior, dependent work would use a known-invalid premise, continuation would
cause destructive or Critical in-scope harm, approved artifacts provide no
compliant path, required acceptance evidence cannot be produced, or a
consultation-gated ruling cannot obtain its consultation. Keep destructive
operations, security-sensitive actions, and external side effects as separate
authority stops.

## Role gates

Adjudication may route a Security or Branch Review finding without changing the
role's technical verdict. Adjudication cannot replace Hardener mutation evidence
or QA acceptance evidence. Fixer Max receives only findings in `REPAIRING`.

## Feature closing

The Branch Reviewer and the Security Reviewer each receive the whole-branch
package and every `DEFERRED`, `DISMISSED`, and `PARKED` finding with its
ruling, cost if wrong, and wake condition, plus every consultation. When either
review reports findings, one `fixer-max` dispatch takes the combined list. Two
scoped re-reviews over the fix range verdict each listed finding `ADDRESSED`
or `NOT ADDRESSED`. Residual findings go to the advisor under C4. There is no
second fix dispatch, no slice replay, and no fresh whole-branch review. Write
every unchanged finding and every consultation to the retrospective and the
branch-completion digest before archive.
