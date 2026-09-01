# GDD obligation-driven orchestration implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make GDD derive every legal action and completion decision from one
durable obligation journal instead of controller prose or mutable projections.

**Architecture:** Add one Bash workflow engine that compiles the current GDD
lifecycle into obligations, writes hash-chained events and immutable evidence,
and reduces those events into ready actions and completion state. Keep
`gdd-slice-state` and `gdd-finding-state` as compatibility adapters, but remove
their direct state authority.

**Tech Stack:** Bash 3.2+, POSIX command-line tools, Git, SHA-256 through
`shasum` or `sha256sum`, and the repository's shell test harnesses.

**Spec:**
`docs/superpowers/specs/2026-09-01-gdd-obligation-driven-orchestration-design.md`

## Global constraints

- Keep stock `skills/subagent-driven-development/` unchanged.
- Add no runtime dependency, daemon, database, or network service.
- Initialize the new engine only for a fresh GDD workspace. If legacy
  `ledger.tsv`, `findings.tsv`, or `findings/` state exists without a v1 workflow
  marker, refuse initialization and leave the workspace byte-for-byte unchanged.
- Preserve the lifecycle order Implementer, Cleaner, Architect, Security
  Reviewer, Hardener, QA, and final Branch Reviewer.
- Preserve exact-delta repair replay, the five-round repair cap, one final repair
  wave, Fable advisory gates, and the final findings digest.
- Hardener mutation evidence and QA acceptance evidence remain mandatory. No
  finding disposition can satisfy or bypass either obligation.
- Use one active action receipt at a time. GDD remains serialized.
- Treat `events.tsv` and copied event evidence as authority. Treat `tasks.md`,
  `ledger.tsv`, `findings.tsv`, and completion files as projections.
- Keep current public command names where callers already use them. Those
  commands must delegate accepted transitions to `gdd-workflow-state`.
- Do not edit `CHANGELOG.md`, generated files, or files outside the paths named
  in this plan.

---

### Task 1: Initialize and reduce a fresh workflow

**Files:**

- Create: `skills/gauntlet-driven-development/scripts/gdd-workflow-state`
- Create: `skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh`
- Modify: `skills/gauntlet-driven-development/scripts/gdd-workspace:1-29`

**Interfaces:**

- Consumes: an approved `PLAN_FILE`, its sibling `tasks.md`, the pinned
  `finding-policy.md`, and the workspace path returned by `gdd-workspace`.
- Produces:
  `gdd-workflow-state PLAN_FILE init|status|next`, workflow format version `1`,
  static obligation records, an empty authoritative event journal, and a pure
  reduced-state report.

- [ ] **Step 1: Write the failing initialization and cutover tests**

Create `gdd-workflow-state.test.sh` with a temporary Git repository and one
valid GDD slice. The fixture must contain the exact role sequence needed by the
compiler. Add these assertions before the executable exists:

```bash
run_workflow "$PLAN_FILE" init
assert_status 0
assert_file "$WORKSPACE/workflow-v1/format-version"
assert_file_contains "$WORKSPACE/workflow-v1/format-version" '1'
assert_file "$WORKSPACE/workflow-v1/obligations.tsv"
assert_file "$WORKSPACE/workflow-v1/events.tsv"
assert_output_contains 'Workflow status: ACTIVE'

run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Ready obligation: slice-1-implementer'
assert_output_contains 'Completion eligible: no'
```

Add a second fixture that creates `ledger.tsv`, `findings.tsv`, and `findings/`
before `init`. Hash the fixture before and after the command and assert:

```bash
assert_status 1
assert_output_contains 'legacy GDD workspace must restart from approved artifacts'
assert_equals "$before_hash" "$after_hash"
assert_not_exists "$WORKSPACE/workflow-v1"
```

Also cover missing `tasks.md`, malformed slice metadata, duplicate slice
numbers, a missing finding policy, and repeated `init` against an unchanged v1
workspace.

- [ ] **Step 2: Run the new test and confirm the RED result**

Run:

```bash
bash skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh
```

Expected: FAIL because `gdd-workflow-state` does not exist.

- [ ] **Step 3: Add the command contract and workspace layout**

Create `gdd-workflow-state` with this public usage contract:

```text
gdd-workflow-state PLAN_FILE init
gdd-workflow-state PLAN_FILE status
gdd-workflow-state PLAN_FILE next
gdd-workflow-state PLAN_FILE format-version
gdd-workflow-state PLAN_FILE claim OBLIGATION_ID ACTOR DISPATCH_FILE
gdd-workflow-state PLAN_FILE accept RECEIPT RESULT_KIND EVIDENCE_FILE [SUPPORTING_FILE...]
gdd-workflow-state PLAN_FILE accept-active OBLIGATION_ID RESULT_KIND EVIDENCE_FILE [SUPPORTING_FILE...]
gdd-workflow-state PLAN_FILE release RECEIPT EVIDENCE_FILE
gdd-workflow-state PLAN_FILE project
gdd-workflow-state PLAN_FILE digest OUTPUT_FILE
gdd-workflow-state PLAN_FILE complete EVIDENCE_FILE
```

Mark both new scripts executable:

```bash
chmod +x skills/gauntlet-driven-development/scripts/gdd-workflow-state \
  skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh
```

Use `gdd-workspace` to resolve the workspace. `init` creates this tree through a
staged directory and one final `mv`:

```text
workflow-v1/
  format-version
  input-digests.tsv
  obligations.tsv
  events.tsv
  events/
  projections/
  rejections/
  recovery/
```

Write `events.tsv` with this fixed header:

```text
sequence\trevision\tevent_id\tobligation_id\tkind\tactor\treceipt\tevidence_path\tevidence_sha256\tprevious_hash\tevent_hash
```

Reject tabs, carriage returns, and newlines in scalar field values. Reuse the
current `shasum` then `sha256sum` fallback.

- [ ] **Step 4: Compile the static lifecycle obligations**

Parse each numbered slice in `tasks.md` and emit these stable obligation IDs:

```text
slice-N-implementer
slice-N-cleaner
slice-N-architect
slice-N-security
slice-N-hardener
slice-N-qa
slice-N-final-suite
slice-N-verified
feature-branch-review
feature-findings-digest
feature-complete
```

Use a tab-separated record with these columns:

```text
obligation_id\tscope\ttype\tprerequisites\tallowed_results\tblocking_boundary\tevidence_contract
```

The first slice's Implementer is ready after initialization. A later slice's
Implementer depends on the prior slice's `slice-N-verified` obligation. The
feature Branch Review depends on every slice verification obligation.

- [ ] **Step 5: Implement the pure reducer and text status projection**

Implement functions with these responsibilities:

```bash
validate_obligations   # validates IDs, references, and the acyclic static graph
validate_event_chain   # validates sequence, revision, hashes, kinds, and evidence
reduce_workflow        # derives obligation states without writing
print_status           # prints status, active claim, ready obligations, and completion
select_next            # returns the first ready obligation in plan order
```

The reducer uses only `obligations.tsv` and the valid ordered events. It returns
`INVALID` at the first gap, unknown version, unknown event kind, broken hash,
missing evidence file, or evidence-digest mismatch. `status` and `next` return
nonzero for `INVALID` and never skip the invalid row.

- [ ] **Step 6: Make `gdd-workspace` refuse mixed legacy and v1 state**

Keep its current path resolution. After creating the plan directory but before
any ledger creation, add a read-only classification helper:

```bash
if [ -e "$dir/workflow-v1/format-version" ]; then
  printf '%s\n' "$dir"
  exit 0
fi

if [ -e "$dir/ledger.tsv" ] || [ -e "$dir/findings.tsv" ] || [ -e "$dir/findings" ]; then
  printf '%s\n' 'legacy GDD workspace must restart from approved artifacts' >&2
  exit 1
fi
```

Do not create legacy ledgers from `gdd-workspace`.

- [ ] **Step 7: Run the focused tests**

Run:

```bash
bash skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh
```

Expected: all initialization, static graph, repeated init, invalid input, and
legacy refusal scenarios pass.

- [ ] **Step 8: Commit the walking skeleton**

```bash
git add skills/gauntlet-driven-development/scripts/gdd-workspace \
  skills/gauntlet-driven-development/scripts/gdd-workflow-state \
  skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh
git commit -m "feat: add GDD obligation journal"
```

### Task 2: Claim actions and accept evidence atomically

**Files:**

- Modify: `skills/gauntlet-driven-development/scripts/gdd-workflow-state`
- Modify: `skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh`

**Interfaces:**

- Consumes: the `ACTIVE` state and ready obligation IDs from Task 1.
- Produces: `claim`, `accept`, and `release` events, opaque `GDD-R...` receipts,
  idempotent result acceptance, crash recovery, and immutable rejection records.

- [ ] **Step 1: Add failing receipt and event-chain tests**

Extend the test with these cases:

```bash
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
receipt=$(extract_field 'Receipt')
assert_matches "$receipt" '^GDD-R[0-9a-f]{64}$'

run_workflow "$PLAN_FILE" next
assert_output_contains 'Resume claim: slice-1-implementer'
assert_output_contains "Receipt: $receipt"

run_workflow "$PLAN_FILE" claim slice-1-cleaner cleaner "$DISPATCH_FILE"
assert_status 1
assert_output_contains 'one action is already claimed'
```

Add valid acceptance, wrong result kind, wrong receipt, stale revision, exact
duplicate retry, conflicting duplicate result, missing evidence, changed
evidence after acceptance, release after dispatch failure, interrupted staged
event recovery, broken event hash, and a missing event evidence directory.

- [ ] **Step 2: Run the tests and confirm the receipt cases fail**

Run:

```bash
bash skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh
```

Expected: Task 1 cases pass and the new claim or accept assertions fail.

- [ ] **Step 3: Add the workspace lock and staged transaction**

Use one `mkdir` lock at `workflow-v1/.lock`. Store the owner PID and process
start string in the lock directory. If the owner still exists, return a busy
error. If the owner is gone, move the lock to `recovery/` before retrying. Do not
use a timed lease.

Stage evidence, the new full `events.tsv`, and a transaction manifest under
`workflow-v1/.stage.${process_id}/`. Publish the evidence directory first, publish the
new journal with `mv` second, then remove the transaction manifest. On the next
command, finish or reject an interrupted transaction by comparing every staged
digest with the manifest.

- [ ] **Step 4: Implement claim and receipt generation**

Under the lock, reduce current state again. Permit `claim` only for the selected
ready obligation. Build the receipt digest from a canonical file containing:

```text
workflow-format: 1
obligation-id: ${obligation_id}
claim-revision: ${next_revision}
actor: ${actor}
dispatch-sha256: ${dispatch_sha256}
nonce-path: ${nonce_basename}
```

Hash that file and prefix the digest with `GDD-R`. Append one `ActionClaimed`
event. Copy the dispatch file into that event's evidence directory.

- [ ] **Step 5: Implement accept, release, and idempotency**

`accept` must verify all of these facts before appending an event:

```text
receipt matches the active claim
obligation is still CLAIMED
RESULT_KIND belongs to the obligation's allowed result set
evidence exists and matches its copied SHA-256 digest
the current revision matches the receipt's claim revision
the actor matches the claim
```

An exact retry with the same receipt, result kind, and evidence digest returns
the existing event ID and exits 0. A different result for a consumed receipt
copies the attempted result into `rejections/`, reports the accepted event ID,
and exits 1. `release` accepts only `DISPATCH_FAILED` evidence before any result
event and returns the obligation to `READY`.

- [ ] **Step 6: Add dynamic invalidation and active-claim recovery**

When `next` sees an active claim, return `RESUME_CLAIM` instead of issuing a new
obligation. Preserve the same receipt until `accept` or `release` succeeds. A
later duplicate result cannot change state.

When an accepted repair changes the current revision, append explicit
`EvidenceInvalidated` events for the role evidence named by the existing replay
table. Never infer invalidation from file timestamps.

- [ ] **Step 7: Run the journal and recovery tests**

Run:

```bash
bash skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh
```

Expected: all receipt, idempotency, stale result, release, corruption, and crash
recovery cases pass.

- [ ] **Step 8: Commit action enforcement**

```bash
git add skills/gauntlet-driven-development/scripts/gdd-workflow-state \
  skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh
git commit -m "feat: enforce GDD action receipts"
```

### Task 3: Route slice and finding state through the engine

**Files:**

- Modify: `skills/gauntlet-driven-development/scripts/gdd-slice-state:1-264`
- Modify: `skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh`
- Modify: `skills/gauntlet-driven-development/scripts/gdd-finding-state:1-849`
- Modify: `skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh`
- Modify: `skills/gauntlet-driven-development/scripts/gdd-workflow-state`
- Modify: `skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh`

**Interfaces:**

- Consumes: the active receipt and typed obligation contract from Task 2, plus
  the existing slice and finding evidence formats.
- Produces: compatibility adapters that can validate and accept only the active
  obligation, role-neutral finding obligations, bounded repair history, replay
  invalidation, and regenerated compatibility projections.

- [ ] **Step 1: Write failing adapter-authority tests**

Extend `gdd-slice-state.test.sh` to initialize v1 and assert that calling
`gdd-slice-state ... implementing` without first claiming
`slice-1-implementer` fails without editing `tasks.md`. Then claim the exact
obligation and assert that the same call succeeds and creates an accepted event.

Add equivalent cases for every current slice transition, including:

```text
IMPLEMENTING -> VERIFYING: CLEANER
VERIFYING: CLEANER -> VERIFYING: ARCHITECT
VERIFYING: ARCHITECT -> VERIFYING: SECURITY
VERIFYING: SECURITY -> VERIFYING: HARDENER
VERIFYING: HARDENER -> VERIFYING: QA
VERIFYING: QA -> VERIFIED
any permitted role state -> REPAIRING
REPAIRING -> VERIFYING: CLEANER
```

Assert that changing the `Slice state` line or `N.V` gate manually does not
change `gdd-workflow-state status` and is repaired by projection regeneration.

- [ ] **Step 2: Write failing role-neutral finding tests**

Retain every current `gdd-finding-state.test.sh` behavior and add an active
receipt precondition to report, supplement, transition, repair-start,
repair-finish, repair-entry, and digest.

Add one fixture for each origin:

```text
Cleaner
Architect
Security Reviewer
Hardener
QA
Branch Reviewer
```

Each reported finding must create `VERIFY_FINDING` and `DISPOSE_FINDING`
obligations. Incomplete reports must create a `SUPPLEMENT_FINDING` obligation
and block disposition. Hardener and QA obligations must remain unsatisfied after
`DEFERRED`, `DISMISSED`, `PARKED`, or `BLOCKED` findings.

- [ ] **Step 3: Run both adapter suites and confirm RED**

Run:

```bash
bash skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh
bash skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh
```

Expected: current behavior remains green where it does not depend on authority,
and new active-receipt cases fail.

- [ ] **Step 4: Convert `gdd-slice-state` into an acceptance adapter**

Keep its current argument validation and evidence-status checks. Replace direct
`tasks.md` edits and direct `ledger.tsv` appends with one call:

```bash
workflow_state="$script_dir/gdd-workflow-state"
"$workflow_state" "$plan" accept-active \
  "$expected_obligation" "$result_kind" "$evidence_file" ${supporting_files[@]+"${supporting_files[@]}"}
```

After acceptance, call `gdd-workflow-state project`. The projection rewrites
only the exact slice-state line and verification gate from reduced state and
regenerates `ledger.tsv` for compatibility.

- [ ] **Step 5: Convert `gdd-finding-state` into an acceptance adapter**

Keep its report-shape, disposition, Fable, repair-round, Git-range, replay, and
digest validators. Replace `publish_event_row` and its private transaction
journal with typed calls to `gdd-workflow-state accept-active`.

Map existing operations to these result kinds:

```text
report         -> FindingReported
supplement     -> FindingSupplemented
transition     -> FindingDispositionRecorded or FindingResolved
repair-start   -> RepairStarted
repair-finish  -> RepairFinished
repair-entry   -> ReplayEntered
digest         -> FindingsDigestWritten
```

The workflow reducer generates stable finding IDs and all dynamic obligations.
The adapter prints the engine-assigned finding ID for `report` so current callers
keep their interface.

- [ ] **Step 6: Implement finding and replay reduction**

Move these decisions into the reducer:

```text
REPORTED blocks the finding's lifecycle boundary
REPAIRING blocks advancement beyond its replay endpoint
BLOCKED blocks only its recorded dependency boundary
DEFERRED, DISMISSED, and PARKED remain digest obligations
wake evidence returns the finding to REPORTED
repair rounds are sequential and capped at five
RESOLVED requires a verified repair finish and all replay obligations
QA-originated or post-QA behavior changes invalidate QA
```

Use the existing origin-to-replay table without changing role order. Generate
dynamic obligation IDs such as `finding-GDD-F0001-verify`.

- [ ] **Step 7: Regenerate projections from reduced state**

Add `gdd-workflow-state project`. It atomically rewrites:

```text
tasks.md slice-state lines and N.V gates
workspace/ledger.tsv
workspace/findings.tsv
workspace/projections/status.tsv
```

Projection failure must leave the authoritative journal accepted and report a
recoverable projection error. The next `status`, `next`, or explicit `project`
must rebuild it. Projection content never feeds the reducer.

- [ ] **Step 8: Run all state suites**

Run:

```bash
bash skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh
bash skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh
bash skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh
```

Expected: all existing finding and slice behavior passes through v1, every
unclaimed transition fails, and projection mutation cannot advance state.

- [ ] **Step 9: Commit the adapters**

```bash
git add skills/gauntlet-driven-development/scripts/gdd-workflow-state \
  skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh \
  skills/gauntlet-driven-development/scripts/gdd-slice-state \
  skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh \
  skills/gauntlet-driven-development/scripts/gdd-finding-state \
  skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh
git commit -m "refactor: route GDD state through obligations"
```

### Task 4: Drive GDD from ready obligations

**Files:**

- Modify: `skills/gauntlet-driven-development/SKILL.md:11-322`
- Modify: `skills/gauntlet-driven-development/scripts/gdd-readiness:1-255`
- Modify: `tests/openspec-gdd/test-gdd-readiness.sh`
- Modify: `tests/personal-fork/test-personal-fork.sh:35-187`
- Modify: `skills/gauntlet-driven-development/scripts/gdd-workflow-state`
- Modify: `skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh`

**Interfaces:**

- Consumes: `next`, `claim`, receipt-bound result acceptance, projections, and
  dynamic finding obligations from Tasks 1 through 3.
- Produces: one controller loop, structured role finding output, autonomous
  continuation, machine-derived interruption, final digest, and completion
  evidence.

- [ ] **Step 1: Add failing controller-contract assertions**

Extend `test-personal-fork.sh` to require these literal concepts in execution
order:

```text
scripts/gdd-workflow-state PLAN_FILE init
scripts/gdd-workflow-state PLAN_FILE next
claim the returned obligation before dispatch
accept only the receipt-bound result
continue while a ready obligation exists
USER_AUTHORITY_REQUIRED
Completion evidence:
```

Assert that `SKILL.md` no longer says the controller decides the next lifecycle
step from its own reconstruction. Keep all existing assertions for finding
fields, Fable gates, repair ordering, mandatory Hardener and QA evidence, final
wave order, and findings disclosure.

- [ ] **Step 2: Add completion and interruption state tests**

In `gdd-workflow-state.test.sh`, build a two-slice workflow and prove:

```text
a parked non-dependent finding leaves the next unrelated obligation READY
a dependent BLOCKED finding prevents only its dependency boundary
USER_AUTHORITY_REQUIRED appears only when no claim or ready obligation remains
Fable unavailability parks a non-dependent finding and does not request the user
feature completion is false before Hardener, QA, final suites, Branch Review, and digest
feature completion is true only after all current obligations are satisfied
```

Delete or reorder each mandatory event in a copy of the completed fixture and
assert `Completion eligible: no` or `Workflow status: INVALID`.

- [ ] **Step 3: Replace procedural next-step prose with one controller loop**

Keep the current technical rules and role contracts, but make every action enter
through this loop:

```text
1. Run `gdd-workflow-state PLAN_FILE next`.
2. If it returns READY, write the exact dispatch or local action evidence.
3. Run `claim` for that obligation before issuing the action.
4. Issue the action and record its actual result.
5. Accept the result through the matching adapter and receipt.
6. Repeat without asking the user.
7. Stop only for INVALID, USER_AUTHORITY_REQUIRED, or COMPLETE.
```

When `next` returns `RESUME_CLAIM`, resume the recorded agent if the harness
still exposes it. Otherwise reissue the same bounded action with the same
receipt. Do not claim a replacement obligation.

- [ ] **Step 4: Make lifecycle reports declare their findings structurally**

Extend the existing `[gdd-finding-report]` addendum with:

```text
Write `Finding count: N` in the role report.
For each finding, write one numbered finding file under FINDINGS_DIR using the
existing ten fields. Use zero only when the role found no technical issue.
```

The role acceptance contract must reject a count that does not match the files,
a duplicate number, an unexpected file, or an origin that differs from the
claimed role. Accept the role result and all `FindingReported` events in one
transaction so the role boundary cannot advance between them.

- [ ] **Step 5: Derive the final digest and completion evidence**

`digest OUTPUT_FILE` reads reduced state and writes every unchanged deferred,
dismissed, and parked finding with its Finding ID, origin, ruling, cost if
wrong, wake condition, and evidence digest. It then accepts
`FindingsDigestWritten` through the active receipt.

`complete EVIDENCE_FILE` succeeds only when the reducer reports no unsatisfied
required obligation. Write `completion.md` with:

```text
Workflow status: COMPLETE
Workflow revision: ${revision}
Journal head SHA-256: ${event_hash}
Branch review evidence: ${branch_review_evidence_path}
Findings digest: ${digest_path} ${digest_sha256}
```

Pass that completion path and findings digest to
`superpowers:finishing-a-development-branch`.

- [ ] **Step 6: Extend readiness for the workflow engine**

Make `gdd-readiness` verify that `gdd-workflow-state` exists, is executable, and
reports supported format version `1`. Keep its current OpenSpec planning,
finding-policy, and stock-SDD compatibility checks unchanged.

Add focused failures for a missing executable, wrong mode, and unsupported
format version to `test-gdd-readiness.sh`.

- [ ] **Step 7: Run the controller and readiness suites**

Run:

```bash
bash skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh
bash tests/openspec-gdd/test-gdd-readiness.sh
bash tests/personal-fork/test-personal-fork.sh
```

Expected: the controller contract, autonomous continuation, interruption,
completion, and readiness scenarios pass.

- [ ] **Step 8: Commit controller integration**

```bash
git add skills/gauntlet-driven-development/SKILL.md \
  skills/gauntlet-driven-development/scripts/gdd-readiness \
  skills/gauntlet-driven-development/scripts/gdd-workflow-state \
  skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh \
  tests/openspec-gdd/test-gdd-readiness.sh \
  tests/personal-fork/test-personal-fork.sh
git commit -m "feat: drive GDD from ready obligations"
```

### Task 5: Prove packaging and adversarial behavior

**Files:**

- Modify: `tests/codex/test-package-codex-plugin.sh:168-249`
- Modify: `tests/personal-fork/test-personal-fork.sh`
- Evidence only: `.superpowers/gdd/gdd-obligation-driven-orchestration/`

**Interfaces:**

- Consumes: the complete engine and controller contract from Tasks 1 through 4.
- Produces: packaged executable evidence, journal mutation evidence,
  before-and-after behavioral evidence, and a final full-suite result.

- [ ] **Step 1: Add failing package assertions**

Require both archive formats to include and preserve executable mode for:

```text
skills/gauntlet-driven-development/scripts/gdd-workflow-state
skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh
```

Do not package repository-only pressure evidence.

- [ ] **Step 2: Run the package test and confirm RED**

Run:

```bash
bash tests/codex/test-package-codex-plugin.sh
```

Expected: FAIL until the new package assertions match the produced archive.

- [ ] **Step 3: Fix package discovery or modes only if the test proves a gap**

The current packager includes the complete `skills/` tree. If the new files are
already present, make no production change. If executable mode is lost, update
only the existing mode-preservation path that handles `gdd-readiness` and
`gdd-finding-state`, then rerun the focused package test.

- [ ] **Step 4: Add an adversarial journal mutation matrix**

Extend `gdd-workflow-state.test.sh` with a completed fixture and one mutation per
copy:

```text
delete an event row
duplicate an event row
swap two rows
change an obligation ID
change a receipt
change an evidence digest
remove Hardener evidence
remove QA evidence
remove the final suite
replace Branch Review evidence
remove the findings digest event
append an unknown event kind
```

Each mutation must produce `INVALID` or `Completion eligible: no`. Restore the
unmutated fixture and prove it still produces `COMPLETE`.

- [ ] **Step 5: Re-run the previously failing behavioral scenarios**

Use fresh controller sessions for the scenarios recorded in:

```text
.superpowers/sdd/2026-09-01-gdd-finding-adjudication/task-6-pressure-report.md
.superpowers/sdd/2026-09-01-gdd-finding-adjudication/task-6-independent-review.md
```

The evaluator must inspect the workflow workspace after each run. A response
that narrates a required action without an accepted event fails. Record GDD and
stock SDD results separately. Include a parity comparison only when both samples
pass their own workflow evaluator.

- [ ] **Step 6: Run the complete verification set**

Run:

```bash
bash skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh
bash skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh
bash skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh
bash tests/openspec-gdd/test-require-bridge-schema.sh
bash tests/openspec-gdd/test-gdd-readiness.sh
bash tests/personal-fork/test-personal-fork.sh
bash tests/codex/test-package-codex-plugin.sh
```

Expected: every suite exits 0 with no failed assertion. Treat any flaky or
intermittent result as blocking.

- [ ] **Step 7: Run static checks**

Run:

```bash
bash -n skills/gauntlet-driven-development/scripts/gdd-workflow-state \
  skills/gauntlet-driven-development/scripts/gdd-workspace \
  skills/gauntlet-driven-development/scripts/gdd-slice-state \
  skills/gauntlet-driven-development/scripts/gdd-finding-state
git diff --check
```

Expected: both commands exit 0 with no output.

- [ ] **Step 8: Commit final verification coverage**

```bash
git add tests/codex/test-package-codex-plugin.sh \
  tests/personal-fork/test-personal-fork.sh \
  skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh
git commit -m "test: harden GDD obligation orchestration"
```

After the final commit, review the complete branch diff against the design. Do
not merge, install, or modify stock SDD until the user reviews the implementation
and its behavioral evidence.
