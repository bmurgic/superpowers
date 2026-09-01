# GDD obligation-driven orchestration design

**Date:** 2026-09-01
**Status:** Approved design. The bare Superpowers implementation plan is
`docs/superpowers/plans/2026-09-01-gdd-obligation-driven-orchestration.md`.
**Scope:** Follow-on design for Gauntlet-Driven Development (GDD). Stock
Subagent-Driven Development (SDD) remains unchanged.

## Why GDD needs a workflow engine

The current GDD finding work added explicit policy, durable records, transition
guards, and repair evidence. Its structural tests pass. Behavioral evaluations
still show that an agent can skip a required step even when `SKILL.md` states
the rule directly.

More prose will not close that gap. A model can omit a rule from its response or
claim that it completed an action. The workflow must instead derive the next
legal action from durable state and reject any action that is not currently
legal.

The design replaces agent-declared progress with obligation-driven progress.
Every required finding decision, repair, replay, lifecycle role, and completion
gate becomes an obligation. GDD completes only when the workflow engine proves
that all required obligations are satisfied.

## Goals

- Make skipped or reordered GDD gates invalid state transitions.
- Continue autonomous work while any legal action remains.
- Apply one finding process to Cleaner, Architect, Security Reviewer, Hardener,
  QA, and Branch Reviewer findings.
- Preserve every finding, decision, repair attempt, and verification result.
- Resume after interruption without trusting conversation history.
- Interrupt the user only when the approved work cannot continue without new
  authority.
- Keep stock SDD unchanged.
- Reuse the current GDD finding policy and state helpers where they still fit.

## Non-goals

- This design does not modify stock SDD.
- This design does not change the approved feature, specification, or role
  order.
- This design does not make Fable Advisor authoritative.
- This design does not replace independent lifecycle roles with a controller
  review.
- This design does not add an external workflow service.
- This design does not implement the architecture.

## Recommended architecture

GDD uses six parts:

1. The obligation compiler converts the approved plan and pinned GDD policy
   into required obligations.
2. The event journal records every accepted workflow fact as an immutable,
   typed event.
3. The reducer reads the event journal and derives the current workflow state.
4. The reconciler selects obligations whose prerequisites are satisfied.
5. The action adapter issues a single-use receipt for one legal action and
   validates the result returned for that receipt.
6. Projections produce human-readable progress, completion evidence, and the
   final findings digest from reduced state.

```text
approved plan + pinned GDD policy
               |
               v
      obligation compiler
               |
               v
   append-only event journal <--- validated role results
               |
               v
      deterministic reducer
               |
               v
          reconciler
               |
               v
 legal action receipt -> role dispatch -> result validation
               |
               v
    progress, completion, and findings digest
```

The journal and reducer are the authority. A command can expose the action
adapter, but the command is only an interface. It cannot make an illegal
transition valid.

## Domain model

### Obligation

An obligation names work that GDD must complete or dispose of before a defined
boundary. Each obligation contains:

- a stable ID;
- its type and scope;
- the policy or approved artifact that requires it;
- prerequisite obligation IDs;
- the evidence contract for completion;
- the allowed result events;
- its wake conditions; and
- whether an unresolved obligation blocks a role, a slice, or the feature.

Examples include `VERIFY_FINDING`, `CONSULT_FABLE`, `REPAIR_FINDING`,
`REPLAY_ROLE`, `RUN_HARDENER`, `RUN_QA`, and `BUILD_FINDINGS_DIGEST`.

An obligation is pending, ready, claimed, satisfied, disposed, or blocked. The
reducer derives the status. An agent does not set it directly.

### Event

An event records one accepted fact. Events are append-only and include:

- a unique event ID;
- the obligation ID;
- the workflow revision used to issue the action;
- the event type;
- evidence references and their digests;
- the actor or role that produced the result; and
- the receipt that authorized the action.

Examples include `FindingReported`, `EvidenceVerified`, `FableConsulted`,
`DispositionRecorded`, `RepairStarted`, `RepairVerified`, `RoleVerified`, and
`DigestWritten`.

Corrections append a superseding event. They do not edit or delete earlier
events.

### Action receipt

The action adapter creates an opaque, single-use receipt for one ready
obligation. The receipt binds the action to:

- the obligation ID;
- the expected workflow revision;
- the permitted result event types;
- the required evidence contract; and
- the assigned role, when the action is a role dispatch.

The adapter rejects expired, consumed, or stale receipts. A result from an old
revision cannot advance current state.

Cryptographic signing is not required for the first local implementation. The
bare plan defines the receipt format and atomicity guarantees.

### Reduced state

The reducer is deterministic. The same approved inputs and ordered events
always produce the same state. Reduced state includes:

- each obligation and its derived status;
- the current role and slice boundary;
- ready actions;
- unresolved dependencies;
- repair-round counts;
- the current revision; and
- completion eligibility.

The reducer never reads prose from an agent response as a workflow decision. A
validator converts a role result into an accepted event only after the result
satisfies its evidence contract.

## Finding lifecycle

A reported finding creates obligations instead of an immediate repair command.
A normal finding follows this sequence:

1. `FindingReported` records the role's claim and evidence.
2. `VERIFY_FINDING` checks the evidence, the approved artifacts, and the stated
   assumptions.
3. The reducer creates `CONSULT_FABLE` when the pinned policy requires an
   advisory ruling.
4. `DISPOSE_FINDING` records `REPAIRING`, `DEFERRED`, `DISMISSED`, `PARKED`, or
   `BLOCKED` with evidence and the cost if the ruling is wrong.
5. A repair disposition creates `REPAIR_FINDING` and the required replay
   obligations.
6. The repair becomes resolved only after every required replay obligation is
   satisfied.
7. An unchanged deferred, dismissed, or parked finding remains available to
   the final findings digest.

This sequence applies to every GDD role. Role-specific policy still controls
what evidence the role must produce. For example, the controller cannot turn
missing Hardener mutation evidence or missing QA acceptance evidence into a
pass.

## Lifecycle obligations

The obligation compiler creates the lifecycle obligations for every slice. It
preserves the current GDD role order and exact-delta replay rules.

Hardener and QA are mandatory obligations. A slice cannot reach `VERIFIED`
without both roles at the required revision. Branch Review remains a feature
obligation after all slices verify.

When a repair changes an earlier approved revision, the reducer invalidates
dependent verification obligations and creates the required replay work. It
does not rely on an agent to remember which roles must run again.

## Autonomous continuation

After each accepted event, the reconciler asks one question: which obligations
are ready now?

If one or more obligations are ready, GDD continues. A blocked obligation does
not stop unrelated obligations that remain safe and useful. GDD interrupts the
user only when all of these conditions hold:

- no eligible action remains;
- at least one required obligation is unresolved;
- resolving it requires authority not present in the approved artifacts; and
- continuing would break the feature, the specification, or a required gate.

Non-blocking findings stay recorded. During branch completion, GDD presents the
unchanged findings once and asks whether the user wants further work.

## Recovery and concurrency

Recovery starts from the approved inputs and the last valid event. The engine
rebuilds state by replaying the journal. Conversation history is not required.

The implementation must enforce these rules:

- Event IDs are idempotent. Replaying the same accepted result does not create
  a second transition.
- Claiming an obligation and consuming its receipt are atomic state changes.
- Every receipt binds to one workflow revision.
- Results for stale revisions are rejected and recorded for diagnosis.
- Event order is explicit. File-system timestamps do not decide order.
- An incomplete event write does not enter the valid journal prefix.
- A crash after dispatch but before result acceptance leaves a recoverable
  claimed obligation with a defined retry rule.

The storage design must make these guarantees testable. The bare plan uses a
hash-chained local event journal, immutable evidence copies, a directory lock,
and staged file replacement. It adds no database or service.

## Relationship to the current GDD implementation

The current implementation remains useful:

- `finding-policy.md` remains the pinned policy source.
- `gdd-finding-state` can become a validated event writer and findings
  projection.
- `gdd-slice-state` can become a validated event writer and slice-state
  projection.
- Existing evidence files can remain external artifacts referenced by digest.
- Existing repair-round, replay, Hardener, QA, and digest rules remain inputs
  to the obligation compiler.

The migration must remove duplicate authority. Once the workflow engine owns a
transition, direct file edits and legacy transition paths must not remain as an
alternate way to advance the run.

## Relationship to stock SDD

Stock SDD remains unchanged. GDD uses a separate workflow adapter because its
policy adds Fable consultation, exact-delta replay, one final repair wave, and
the findings digest.

Shared behavior is a compatibility target, not a runtime dependency. GDD keeps
the SDD expectations for independent review, bounded repair, Hardener, QA, and
autonomous continuation unless stock SDD explicitly changes those policies.

Parity evaluations must compare valid outcomes. A stock SDD sample establishes
expected policy only when that sample passes its own SDD evaluation. A failing
stock sample cannot redefine GDD behavior.

## Tests

The future implementation needs tests at four levels:

1. Reducer property tests generate valid and invalid event sequences. They
   prove that illegal transitions never produce a completed state.
2. Mutation tests delete, duplicate, reorder, and corrupt events. They prove
   that missing gates and invalid journal states fail closed.
3. Action-adapter tests cover stale receipts, duplicate results, wrong roles,
   missing evidence, concurrent claims, and crash recovery.
4. Fresh-agent evaluations exercise the public GDD workflow. They test whether
   an agent can use the engine and recover from errors. They do not serve as the
   enforcement boundary.

The acceptance suite must include the behavioral scenarios that failed after
the current finding-adjudication work. The new architecture passes only when
those scenarios cannot reach an illegal completed state, even if the agent
tries to skip the required action.

## Alternatives considered

### Add one completion command

A completion command would guard the final transition, but it would not prevent
skipped intermediate work or fabricated evidence. It is useful only as an
adapter over authoritative state.

### Add more policy wording

The current failures already contradict literal rules. More wording increases
prompt size without removing the agent's ability to omit a step.

### Add a shadow reviewer or agent quorum

Another agent can make a different mistake and adds cost to every transition.
Review remains valuable for technical judgment, but agents must not vote the
workflow into a valid state.

### Use capabilities without an event journal

Receipts restrict immediate actions, but they do not provide durable recovery,
audit history, or deterministic reconstruction after interruption.

### Use an event journal without restricted actions

The journal records what happened, but an unrestricted writer can still append
an illegal transition. The action adapter and receipt validation prevent that
write.

## Implementation decisions

The bare plan uses these implementation boundaries:

- `events.tsv` is the authoritative hash-chained event journal. Each event
  points to an immutable evidence copy and its SHA-256 digest.
- A directory lock and staged file replacement make claims and accepted results
  atomic without adding a database.
- Workflow, obligation, and event formats start at version `1`. Unknown versions
  fail closed.
- One action can be claimed at a time. Recovery returns the same receipt until
  the result is accepted or a recorded dispatch failure releases it.
- The engine initializes only fresh workspaces. Existing runs using legacy GDD
  state must restart from their approved artifacts.
- `gdd-finding-state` and `gdd-slice-state` remain command adapters. They stop
  writing authoritative state directly.

## Acceptance criteria for implementation

The follow-on OpenSpec change must prove all of these outcomes:

- An agent cannot advance a slice by claiming that a required action occurred.
- Every accepted transition names the obligation and evidence that authorized
  it.
- GDD resumes from durable state after conversation loss or process
  interruption.
- GDD continues while unrelated legal work remains.
- GDD asks the user only when no legal continuation exists without new
  authority.
- Mandatory Hardener and QA obligations cannot be dismissed, parked, or
  bypassed.
- The final findings digest is derived from the journal.
- Stock SDD files and runtime behavior do not change.
- The current failed behavioral scenarios pass without weakening their
  requirements.

## Relationship to the current branch

This artifact records a follow-on design for
`codex/gdd-finding-adjudication`. The bare Superpowers plan at
`docs/superpowers/plans/2026-09-01-gdd-obligation-driven-orchestration.md`
implements it without creating an OpenSpec change.

The plan does not authorize implementation until the user selects an execution
route.
