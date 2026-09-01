# GDD Finding Adjudication Design

**Date:** 2026-09-01
**Status:** Draft for review

## Context

Gauntlet-Driven Development (GDD) currently routes every blocking lifecycle
finding directly to repair. The originating role supplies a technical verdict,
and the controller treats that verdict as a workflow decision.

That behavior caused a real failure during the `zed-ftp` change. The Security
Reviewer assumed a hostile local repository and Git configuration, then required
a clean and process-filter preflight that was outside the approved single-user,
trusted-workstation threat model. GDD routed the finding to repair without first
testing the threat premise or deciding whether the proposed repair belonged in
the approved change. The repair expanded the implementation, and a later Cleaner
pass found a possible pipe deadlock in the added mechanism.

Stock Subagent-Driven Development (SDD) handles review findings more carefully.
The reviewer reports evidence and severity. The controller verifies the claim,
runs a bounded repair loop, records rulings, parks non-dependent residuals, and
stops only when no defensible path remains. GDD needs the same separation of
responsibility across Cleaner, Architect, Security Reviewer, Hardener, QA, and
Branch Reviewer.

This fork will not extract or modify SDD's policy. SDD is tuned throughout its
skill, prompts, ledger format, examples, and evaluations. A behavior-preserving
extraction would add substantial regression risk. GDD will instead own a
standalone finding policy derived from the current SDD behavior.

## Goals

- Treat every lifecycle finding as a technical claim that GDD must verify.
- Apply one finding policy regardless of which GDD role reports the finding.
- Continue without routine user decisions.
- Repair valid in-scope findings through a bounded, reviewed loop.
- Prevent unsupported threat premises from expanding the approved change.
- Use Fable Advisor before scope-changing dispositions and repairs.
- Preserve every deferred, dismissed, or parked finding through final review.
- Present unchanged findings once, during branch completion.
- Detect future changes to the relevant stock SDD policy without modifying SDD.

## Non-goals

- Do not modify stock SDD, its prompts, scripts, tests, or runtime behavior.
- Do not invoke SDD as a controller during an OpenSpec GDD run.
- Do not make Fable Advisor authoritative over the user or approved artifacts.
- Do not weaken Hardener mutation evidence or QA acceptance requirements.
- Do not let lifecycle roles decide whether GDD repairs, defers, dismisses,
  parks, or blocks on their own findings.
- Do not make this Fable-specific fork behavior an upstream Superpowers core
  proposal. Superpowers core does not accept third-party service dependencies.
- Do not redesign OpenSpec planning, GDD readiness, or the lifecycle role order.

## Decisions

### D1. Give GDD one standalone finding policy

Create `skills/gauntlet-driven-development/finding-policy.md`. It is a reference
file, not an independently activated skill. GDD reads it before the first slice
and applies it throughout the run.

The policy owns:

- the finding evidence contract;
- authority and adjudication rules;
- severity and disposition separation;
- the repair limit;
- Fable consultation gates;
- continuation and interruption rules;
- wake conditions; and
- final review and disclosure requirements.

`skills/gauntlet-driven-development/SKILL.md` remains the controller. It owns
OpenSpec slice execution, lifecycle order, exact repair replay, verification,
and feature closing. The skill references the policy instead of duplicating its
rules.

SDD remains stock. GDD does not load or snapshot SDD at runtime.

### D2. Snapshot the policy for each run

At workspace creation, GDD copies the current finding policy into the
plan-scoped workspace and records its SHA-256 digest. The active run uses that
snapshot after interruption or compaction. An update to the installed fork
cannot change the rules halfway through a feature.

`gdd-readiness` fails before workspace creation when the policy file is missing
or malformed. A resumed run fails when its recorded digest and snapshot do not
agree. A new run uses the current installed policy.

### D3. Keep technical verdicts separate from workflow dispositions

A lifecycle role decides whether its own verification passed. It reports the
evidence, severity, failure scenario, and proposed repair. The role does not
decide what GDD does next.

The GDD controller decides the workflow disposition after it checks the report
against the codebase and approved artifacts. Role text such as "findings route
to a fixer" is not binding on the controller. The standalone finding policy is
authoritative for GDD routing.

This distinction preserves strict role gates:

- The Security Reviewer's `CLEAN` or `FINDINGS` status is a security verdict.
- The Hardener may report `VERIFIED` only after it produces all required
  mutation and quality evidence.
- QA may report `VERIFIED` only after every approved public-interface procedure
  and required command passes.
- The Branch Reviewer's `Approve` or `Block` status is a whole-branch technical
  verdict.

GDD may dismiss, defer, or park a Security or Branch Review finding after
adjudication. GDD may not convert missing Hardener or QA evidence into a pass.
If required verification cannot be produced, the feature is incomplete.

### D4. Use one role-neutral finding record

Every lifecycle dispatch includes a finding-reporting addendum. The originating
role supplies the fields it can establish:

| Field | Meaning |
| --- | --- |
| Origin role | Cleaner, Architect, Security Reviewer, Hardener, QA, or Branch Reviewer |
| Severity claim | The role's technical severity |
| Blocking claim | Whether the role believes its own gate failed |
| Observed failure | The concrete incorrect behavior or missing evidence |
| Evidence | File, line, command, trace, screenshot, or report reference |
| Violated authority | The requirement, scenario, QA procedure, invariant, or project rule |
| Assumptions | Threat model, environment, state, caller, or dependency premises |
| Failure scenario | A reproducible or traceable path from the premise to the failure |
| Proposed repair | The smallest repair the role can identify |
| Repair effects | Expected behavior, architecture, dependency, or operational changes |

The controller assigns the finding ID, fills any controller-owned fields, and
records the finding before it changes slice state. Missing fields do not erase a
finding. The controller either verifies the missing information or records why
the field does not apply.

### D5. Use explicit finding states

The finding ledger uses these states:

| State | Meaning | May the run continue? |
| --- | --- | --- |
| `REPORTED` | The finding is captured but not adjudicated | No past the current role boundary |
| `REPAIRING` | The finding is valid, binding, and fixable in approved scope | No past the current role boundary |
| `RESOLVED` | The required replay verified the repair | Yes |
| `DEFERRED` | The finding is valid but outside the approved change | Yes |
| `DISMISSED` | The evidence does not support the finding, or the requirement is already satisfied | Yes |
| `PARKED` | The finding is unresolved or contested, but no remaining work depends on it | Yes |
| `BLOCKED` | No safe, compliant path exists without user authority | No |

There is no ordinary `NEEDS_DECISION` state. A redesign concern becomes
`PARKED` when the approved feature can still finish. It becomes `BLOCKED` when
the feature cannot finish without choosing new behavior.

Allowed state paths are:

```text
REPORTED -> REPAIRING -> RESOLVED
REPORTED -> DEFERRED | DISMISSED | PARKED | BLOCKED
REPAIRING -> DEFERRED | DISMISSED | PARKED | BLOCKED
DEFERRED | DISMISSED | PARKED -> REPORTED when a wake condition becomes true
BLOCKED -> REPORTED after the user supplies the missing authority
```

### D6. Verify before repair or disposition

For every reported finding, the controller:

1. Restates the technical claim.
2. Verifies the evidence against the current code and reports.
3. Compares the claim with the approved specification, design, Gherkin, QA
   procedures, task slice, and explicit non-goals.
4. Tests each assumption and threat premise against the actual deployment and
   operating context.
5. Checks whether the proposed repair preserves existing behavior and approved
   architecture.
6. Chooses a disposition and records why it is correct and what it costs if
   wrong.

The controller must not tell reviewers which issues to suppress. Reviewers
report their technical conclusions. GDD adjudicates those conclusions after
the report exists.

### D7. Use a bounded five-round repair loop

Confirmed findings enter the repair loop when they violate a binding
specification requirement or their originating role's severity vocabulary maps
them to Critical, Major, or Important impact, and a repair fits the approved
scope. Minor and clearly unrelated observations do not enter the loop.

GDD permits up to five repair rounds for one finding family:

- Round 1 uses `fixer`.
- Rounds 2 through 5 use fresh `fixer-max` agents after the first repair fails.
- Every round must use new evidence or a different falsifiable repair
  hypothesis.
- Every repair runs the existing exact-delta replay through the role that
  caused the repair.
- The loop ends as soon as the required replay verifies the repair.
- When no different credible repair remains, the controller adjudicates
  instead of dispatching an identical attempt.

The controller does not repair findings itself. A repair without an independent
replay remains unverified.

### D8. Consult Fable only at scope-changing gates

GDD invokes `fable-advisor:advise` before:

- `DEFERRED`;
- `DISMISSED`;
- `PARKED`;
- `BLOCKED`; and
- a repair that adds a dependency, subprocess, concurrency, persistence,
  credentials, an external side effect, a contract change, or new approved
  behavior.

Fable does not review an ordinary in-scope repair. The user may request Fable
for any finding.

The dispatch gives Fable the original finding, approved artifacts, verified
facts, assumptions, proposed disposition, cost if wrong, and any repair
history. Fable may recommend a disposition or a smaller repair. The controller
records the advisory result. The user and approved artifacts remain
authoritative.

When Fable is unavailable, GDD records the failed consultation. A finding that
does not affect remaining work becomes `PARKED` with `advisor unavailable` in
its ruling, and the run continues. A finding that prevents safe completion
becomes `BLOCKED`. GDD does not substitute another advisor.

### D9. Interrupt only when completion is not defensible

A finding may interrupt the user during the run only when at least one of these
conditions is true:

1. An accepted requirement cannot be satisfied without choosing new behavior.
2. A dependent slice would build on a known-invalid interface or premise.
3. Continuing would create destructive, irreversible, or Critical in-scope
   harm.
4. Approved artifacts contradict each other and provide no compliant path.
5. Required acceptance evidence cannot be produced.

All other findings receive a recorded disposition, and GDD continues.

Destructive operations, publishing, pushing, merging, and other authority
boundaries remain separate stop conditions. They are not finding
dispositions.

### D10. Wake findings when later evidence changes the ruling

Every `DEFERRED`, `DISMISSED`, or `PARKED` finding records a wake condition.
GDD returns the finding to `REPORTED` when:

- a later slice changes the affected code or interface;
- a dependent task relies on the disputed premise;
- new evidence contradicts the ruling;
- the Branch Reviewer finds a cross-slice consequence; or
- the recorded condition becomes true.

When a later dispatch touches the affected area, the dispatch includes the
finding ID, ruling, cost if wrong, and wake condition.

### D11. Keep role changes at the GDD handoff boundary

The lifecycle roles keep their existing specialties and verification
standards. GDD adds a finding-reporting addendum to each dispatch and treats the
returned status as evidence.

- Cleaner reports anything it cannot resolve with a behavior-preserving
  cleanup.
- Architect reports unsettled architecture or behavior decisions.
- Security Reviewer reports vulnerabilities and threat premises without
  deciding the workflow disposition.
- Hardener keeps strict mutation and quality gates. Non-blocking observations
  use the common finding record.
- QA keeps strict acceptance gates. An approved scenario failure remains a
  feature failure. An unrelated observation does not fail the slice.
- Branch Reviewer receives every unresolved or unchanged finding and rechecks
  its wake condition.
- Fixer and Fixer Max receive only findings in `REPAIRING`.

The first implementation does not broadly rewrite the installed role source
files. GDD's dispatch contract and controller policy resolve routing language
inside those role prompts. A role prompt changes only if behavioral evaluation
shows that the dispatch contract cannot make the role report the required
evidence.

### D12. Store findings separately from slice transitions

The current `ledger.tsv` remains dedicated to machine slice transitions.
`gdd-slice-state` parses fixed fields from that file, so arbitrary finding rows
would corrupt its state model.

Add a plan-scoped finding ledger and a `gdd-finding-state` helper. The helper
owns finding creation and state transitions. Each record contains:

- finding ID;
- slice and origin role;
- severity and blocking claims;
- current state;
- evidence and report paths;
- repair rounds and commit ranges;
- controller ruling;
- Fable report or unavailable status;
- cost if wrong;
- wake condition; and
- transition history.

`gdd-slice-state` consults the finding ledger before it advances a role boundary
or marks a slice `VERIFIED`:

- `REPORTED`, `REPAIRING`, and `BLOCKED` prevent advancement.
- `DEFERRED`, `DISMISSED`, and `PARKED` require a complete ruling, cost if
  wrong, wake condition, and required Fable evidence.
- `RESOLVED` requires the expected replay evidence.

The Security Reviewer may return `FINDINGS` and still hand off to Hardener only
after the controller records an allowed terminal disposition for every
finding. Hardener and QA still require their own `VERIFIED` statuses because
their evidence cannot be replaced by adjudication.

### D13. Recheck and disclose findings during feature closing

After the final verified slice, the Branch Reviewer receives:

- the full branch package;
- the approved OpenSpec artifacts;
- every `DEFERRED`, `DISMISSED`, and `PARKED` finding;
- each ruling and cost if wrong; and
- each wake condition.

The controller adjudicates the Branch Reviewer's technical verdict. A woken
finding receives one final repair wave and one exact scoped re-review. Residual
non-blocking findings remain recorded.

Before OpenSpec archives the active change, the retrospective receives a
durable `Findings left unchanged` section. It lists each finding ID, origin,
severity, summary, final disposition, reason, Fable result, and cost if wrong.

During `superpowers:finishing-a-development-branch`, GDD presents one batched
checkpoint before the normal integration menu:

```text
These findings were left unchanged. Do you want action on any of them?

1. No, continue to the branch options.
2. Yes, create follow-up work for selected findings.
3. Ask Fable to reconsider selected findings.
```

The normal merge, pull request, or keep-branch menu remains unchanged. The GDD
workspace is not deleted until the durable digest exists and the checkpoint has
been presented.

### D14. Detect drift from stock SDD without changing it

The standalone policy records the stock SDD revision and the fingerprints of
the policy sections used as its starting point. A focused compatibility test
fails when a later fork update changes those sections.

The failure does not copy new SDD text into GDD. It requires a maintainer to
compare the changed SDD behavior with the standalone GDD policy, update GDD
when appropriate, and accept a new fingerprint. Active runs remain pinned to
their saved policy snapshot.

Behavioral parity evaluations exercise the same finding scenarios through SDD
and GDD. The expected dispositions match unless a declared GDD addition, such
as Fable consultation or lifecycle replay, explains the difference.

## Components and data flow

```text
lifecycle role reports technical finding
                    |
                    v
          GDD records REPORTED
                    |
                    v
      verify code, artifacts, and premises
                    |
          +---------+---------+
          |                   |
          v                   v
   in-scope repair       scope disposition
          |                   |
          v                   v
 five-round repair       Fable consultation
 and delta replay             |
          |                   v
          v          DEFERRED | DISMISSED
       RESOLVED        PARKED | BLOCKED
          |                   |
          +---------+---------+
                    |
                    v
        next role or user interruption
                    |
                    v
  Branch Reviewer rechecks unchanged findings
                    |
                    v
 retrospective digest and final batched checkpoint
```

## File map

- Create `skills/gauntlet-driven-development/finding-policy.md` as the
  standalone policy.
- Modify `skills/gauntlet-driven-development/SKILL.md` to load the policy,
  adjudicate every lifecycle finding, run the bounded repair loop, and hand the
  final digest to branch completion.
- Create `skills/gauntlet-driven-development/scripts/gdd-finding-state` to own
  the finding ledger.
- Create `skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh`
  for state and evidence tests.
- Modify `skills/gauntlet-driven-development/scripts/gdd-readiness` to verify
  the standalone policy before workspace creation.
- Modify `skills/gauntlet-driven-development/scripts/gdd-slice-state` to check
  the finding ledger at role boundaries and slice verification.
- Extend `skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh`
  for adjudicated Security findings and unresolved finding guards.
- Modify `skills/finishing-a-development-branch/SKILL.md` to accept and present
  an optional controller-provided findings digest before its existing menu.
- Add focused personal-fork tests for policy loading, SDD drift detection,
  Fable routing, role-neutral dispatches, and final disclosure.
- Do not modify `skills/subagent-driven-development/`.

## Error handling

- A missing or malformed finding policy stops GDD before workspace creation.
- An invalid finding transition fails without changing the finding ledger,
  `tasks.md`, or the slice transition ledger.
- A missing role report or evidence path keeps the finding `REPORTED`.
- A missing ruling, cost if wrong, wake condition, or required Fable result
  prevents a non-repair disposition.
- A failed repair keeps the finding open and extends the existing repair range.
- Missing Hardener or QA verification remains a feature blocker.
- A missing final digest prevents GDD workspace deletion but does not delete or
  rewrite implementation commits.
- A stock SDD fingerprint change fails the compatibility test. It does not
  alter active GDD behavior.

## Risks and mitigations

- **R1: The standalone policy drifts from SDD.** Detect changes to the source
  SDD sections and run behavioral parity evaluations after fork updates.
- **R2: Role prompts keep automatic routing language.** Make GDD's dispatch and
  controller policy authoritative for routing. Change a role prompt only when
  behavioral evidence proves the handoff contract is insufficient.
- **R3: GDD dismisses a real vulnerability.** Require concrete code and threat
  verification, Fable review, a recorded cost if wrong, a wake condition, and
  Branch Reviewer reconsideration.
- **R4: Fable becomes an authorization source.** Record its answer as advisory
  evidence and keep approved artifacts and user decisions authoritative.
- **R5: Five GDD repair rounds become expensive.** Stop when verification
  passes or credible repair hypotheses are exhausted. Require each attempt to
  add evidence or use a different falsifiable hypothesis.
- **R6: Finding records corrupt slice state.** Keep a separate ledger and make
  one helper own its transitions.
- **R7: Final disclosure occurs after evidence disappears.** Write the durable
  retrospective digest before archive and keep the GDD workspace until branch
  completion presents it.
- **R8: Strict role evidence is weakened to preserve momentum.** Never replace
  Hardener mutation evidence or QA acceptance evidence with a controller
  ruling.

## Verification

Focused deterministic tests must cover:

- every legal and illegal finding-state transition;
- required evidence for each terminal disposition;
- unresolved findings blocking role and slice advancement;
- an adjudicated Security `FINDINGS` verdict advancing to Hardener;
- Hardener and QA non-verified statuses remaining blocking;
- wake conditions returning findings to `REPORTED`;
- five-round repair limits and Fixer Max escalation;
- policy snapshot and resume behavior;
- stock SDD fingerprint drift;
- zero-finding and multiple-finding branch completion; and
- preservation of the existing branch integration menu.

Fresh-agent behavioral evaluations must cover:

1. A Security finding based on an excluded hostile-local-repository premise is
   verified, sent to Fable, dismissed or parked with evidence, and carried to
   final disclosure without an automatic repair.
2. A valid in-scope Critical finding enters repair and exact-delta replay
   without asking the user.
3. A non-dependent architecture concern is parked and the next slice starts.
4. A later slice wakes a parked finding before it depends on the disputed
   interface.
5. A contradictory specification with no compliant implementation becomes
   `BLOCKED` after Fable review.
6. Fable unavailability parks a non-dependent finding but blocks a finding that
   prevents verification.
7. Cleaner, Architect, Security Reviewer, Hardener, QA, and Branch Reviewer
   findings all enter the same controller policy.
8. The Branch Reviewer wakes a cross-slice finding, followed by one final fix
   wave and one scoped re-review.
9. Branch completion presents every unchanged finding once with its ruling and
   cost if wrong.
10. A run with no unchanged findings reaches the existing integration menu
    without an extra prompt.

The completed implementation must also pass the existing GDD, personal-fork,
shell-lint, and package tests, plus `git diff --check`. Skill behavior changes
require before-and-after pressure evidence under `superpowers:writing-skills`.
