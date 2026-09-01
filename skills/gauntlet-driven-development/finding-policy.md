# GDD finding policy

Policy-Version: 1
SDD-Policy-Revision: 6.3.0
SDD-Policy-SHA256: 5ac459493100dce8eec430d4637d03945c1e270be6eca251dddd74186558f120

## Authority

Lifecycle roles report technical findings and verification verdicts. The GDD
controller verifies each finding and chooses its workflow disposition. The
approved OpenSpec artifacts and explicit user decisions are binding. Fable is
advisory.

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

`REPORTED` and `BLOCKED` stop lifecycle advancement. `REPAIRING` permits only
the exact-delta replay through its recorded endpoint. `RESOLVED`, `DEFERRED`,
`DISMISSED`, and `PARKED` permit later lifecycle work after their required
evidence passes validation.

## Adjudication

For each finding, the controller restates the claim, checks the cited evidence,
compares it with the approved artifacts, tests its assumptions and threat
premises, checks the proposed repair's effects, and records the disposition,
reason, and cost if wrong. The controller does not pre-judge reviewer output or
tell a role which findings to suppress.

## Repair

Confirmed in-scope Critical, Major, Important, or specification findings enter
the repair loop. Round 1 uses `fixer`. Rounds 2 through 5 use a fresh
`fixer-max`. Every attempt needs new evidence or a different falsifiable
hypothesis. Every repair uses GDD's existing exact-delta replay. The controller
does not edit the implementation itself.

## Fable

Consult `fable-advisor:advise` before `DEFERRED`, `DISMISSED`, `PARKED`,
`BLOCKED`, or a repair that adds a dependency, subprocess, concurrency,
persistence, credentials, external side effect, contract change, or new
approved behavior. Record the result. If Fable is unavailable, park a
non-dependent finding with the failed consultation and block only when the
finding prevents safe completion.

## Interruption

Interrupt the user for a finding only when an accepted requirement needs new
behavior, dependent work would use a known-invalid premise, continuation would
cause destructive or Critical in-scope harm, approved artifacts provide no
compliant path, or required acceptance evidence cannot be produced. Keep
destructive operations, security-sensitive actions, and external side effects
as separate authority stops.

## Role gates

Adjudication may route a Security or Branch Review finding without changing the
role's technical verdict. Adjudication cannot replace Hardener mutation evidence
or QA acceptance evidence. Fixer and Fixer Max receive only findings in
`REPAIRING`.

## Feature closing

The Branch Reviewer receives every `DEFERRED`, `DISMISSED`, and `PARKED`
finding, its ruling, its cost if wrong, and its wake condition. Batch every new
or woken final finding into one fix dispatch. Replay every affected slice, then
run one fresh whole-branch Branch Reviewer. Do not run a second final fix wave.
Write every unchanged finding to the retrospective and the branch-completion
digest before archive.

## Stock SDD compatibility

The SDD digest covers continuous execution and rulings, task-review finding
handling, the five-round fix loop, final review, and final ruling disclosure.
A digest mismatch stops new GDD runs for maintainer review. It never modifies
SDD or an active GDD policy snapshot.
