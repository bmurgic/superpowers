# GDD finding adjudication implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make GDD verify and adjudicate every lifecycle finding before it decides whether to repair, defer, dismiss, park, or block.

**Architecture:** Add one GDD-owned finding policy and an append-only, plan-scoped finding-state helper. `gdd-slice-state` consults that helper before lifecycle transitions, while the GDD controller remains responsible for evidence review, Fable consultation, bounded repairs, exact-delta replay, and final disclosure. Stock SDD and the lifecycle role source files do not change.

**Tech stack:** Markdown skills, Bash 3.2-compatible scripts, `awk`, `grep`, `sed`, SHA-256 through `shasum` or `sha256sum`, existing shell-test helpers, and fresh-agent pressure tests.

**Spec:** `docs/superpowers/specs/2026-09-01-gdd-finding-adjudication-design.md`

## Global constraints

- Do not modify `skills/subagent-driven-development/` or stock SDD behavior.
- Do not run SDD and GDD as concurrent controllers for one OpenSpec change.
- Do not modify Cleaner, Architect, Security Reviewer, Hardener, QA, Branch Reviewer, Fixer, or Fixer Max source files in this plan.
- Treat every lifecycle finding as a technical claim. The reporting role does not choose the workflow disposition.
- Keep Hardener mutation evidence and QA acceptance evidence mandatory. A controller ruling cannot replace either gate.
- Keep GDD's lifecycle order and exact-delta replay rules intact.
- Use the same finding policy for Cleaner, Architect, Security Reviewer, Hardener, QA, and Branch Reviewer.
- Invoke Fable before `DEFERRED`, `DISMISSED`, `PARKED`, `BLOCKED`, or a scope-expanding repair. Fable remains advisory.
- Continue without a user decision unless a D9 interruption condition or a separate destructive, security-sensitive, or external authority boundary applies.
- Use at most five repair rounds for a slice finding family. Use `fixer` in round 1 and a fresh `fixer-max` in rounds 2 through 5.
- During feature closing, batch all new and woken Branch Reviewer findings into one fix dispatch. Replay every affected slice, run one fresh whole-branch Branch Reviewer, and do not run a second final fix wave.
- Keep the GDD finding ledger separate from the existing four-field `ledger.tsv` slice-transition log.
- Keep all new shell code compatible with the macOS Bash 3.2 runtime.
- Add no runtime dependency.
- Preserve the pre-existing uncommitted change in `skills/direct-development/SKILL.md`.

## File structure

- Create `skills/gauntlet-driven-development/finding-policy.md` as the installed, GDD-owned policy reference.
- Create `skills/gauntlet-driven-development/scripts/gdd-finding-state` as the only writer for the finding ledger, policy snapshot, transition artifacts, and final digest.
- Create `skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh` for the helper's state machine and artifact validation.
- Modify `skills/gauntlet-driven-development/scripts/gdd-readiness` to validate the installed policy and detect stock SDD policy drift.
- Modify `tests/openspec-gdd/test-gdd-readiness.sh` for policy and compatibility failures.
- Modify `skills/gauntlet-driven-development/scripts/gdd-slice-state` to guard lifecycle transitions with finding state.
- Modify `skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh` for adjudicated Security findings, repair replay, and strict Hardener and QA gates.
- Modify `skills/gauntlet-driven-development/SKILL.md` to load the snapshot and apply the policy throughout the lifecycle.
- Modify `skills/finishing-a-development-branch/SKILL.md` to accept an optional GDD findings digest before the existing integration menu.
- Modify `tests/personal-fork/test-personal-fork.sh` for the policy, controller, Fable, and final-disclosure contracts.
- Modify `tests/codex/test-package-codex-plugin.sh` to verify that packaged plugins include the policy and preserve the new helper's executable mode.

---

### Task 1: Add the standalone policy and SDD compatibility guard

**Executor:** implementer
**Delivers:** New GDD runs reject a missing, malformed, or stock-SDD-incompatible finding policy while resumed runs remain pinned to their validated snapshot.
**Depends on:** none

**Files:**

- Create: `skills/gauntlet-driven-development/finding-policy.md`
- Modify: `skills/gauntlet-driven-development/scripts/gdd-readiness`
- Modify: `tests/openspec-gdd/test-gdd-readiness.sh`

**Interfaces:**

- Consumes: the finding rules in the approved design and the current stock SDD policy sections.
- Produces: a policy with `Policy-Version: 1`, `SDD-Policy-Revision: 6.3.0`, and `SDD-Policy-SHA256: 5ac459493100dce8eec430d4637d03945c1e270be6eca251dddd74186558f120`.
- Produces: `gdd-readiness CHANGE_DIRECTORY` fails with one `FAIL:` line for a missing policy, malformed metadata, missing SDD source, incomplete section extraction, or a digest mismatch.
- Preserves: a resumed run validates its saved snapshot and does not adopt or reject a later installed-policy change.

- [ ] **Step 1: Add failing readiness fixtures for policy validation**

Extend `tests/openspec-gdd/test-gdd-readiness.sh` with a copied skill tree so each test can alter the policy or SDD source without changing the checkout:

```bash
make_skill_fixture() {
  local fixture_name="$1"
  local fixture_root="$TEST_ROOT/$fixture_name-skills"
  local fixture_policy

  mkdir -p "$fixture_root"
  cp -R "$REPO_ROOT/skills/gauntlet-driven-development" "$fixture_root/"
  cp -R "$REPO_ROOT/skills/subagent-driven-development" "$fixture_root/"
  fixture_policy="$fixture_root/gauntlet-driven-development/finding-policy.md"
  cat >"$fixture_policy" <<'EOF'
# GDD finding policy
Policy-Version: 1
SDD-Policy-Revision: 6.3.0
SDD-Policy-SHA256: 5ac459493100dce8eec430d4637d03945c1e270be6eca251dddd74186558f120
## Authority
## Finding report
## Finding states
## Adjudication
## Repair
## Fable
## Interruption
## Role gates
## Feature closing
## Stock SDD compatibility
EOF
  printf '%s\n' "$fixture_root/gauntlet-driven-development/scripts/gdd-readiness"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    sha256sum "$1" | awk '{ print $1 }'
  fi
}

ORIGINAL_READINESS="$READINESS"

READINESS="$(make_skill_fixture missing-finding-policy)"
rm -f "$(dirname "$READINESS")/../finding-policy.md"
run_readiness "$VALID_CHANGE"
assert_status 1
assert_contains 'FAIL: GDD finding policy is missing or empty'

READINESS="$(make_skill_fixture malformed-finding-policy)"
sed -i.bak '/^Policy-Version:/d' "$(dirname "$READINESS")/../finding-policy.md"
rm "$(dirname "$READINESS")/../finding-policy.md.bak"
run_readiness "$VALID_CHANGE"
assert_status 1
assert_contains 'FAIL: GDD finding policy must contain exactly one Policy-Version: 1'

READINESS="$(make_skill_fixture wrong-sdd-policy-revision)"
sed -i.bak 's/^SDD-Policy-Revision:.*/SDD-Policy-Revision: 0.0.0/' \
  "$(dirname "$READINESS")/../finding-policy.md"
rm "$(dirname "$READINESS")/../finding-policy.md.bak"
run_readiness "$VALID_CHANGE"
assert_status 1
assert_contains 'FAIL: GDD finding policy must contain exactly one SDD-Policy-Revision: 6.3.0'

READINESS="$(make_skill_fixture duplicate-sdd-policy-digest)"
printf '%s\n' \
  'SDD-Policy-SHA256: 5ac459493100dce8eec430d4637d03945c1e270be6eca251dddd74186558f120' \
  >>"$(dirname "$READINESS")/../finding-policy.md"
run_readiness "$VALID_CHANGE"
assert_status 1
assert_contains 'FAIL: GDD finding policy must contain exactly one SDD-Policy-SHA256: 5ac459493100dce8eec430d4637d03945c1e270be6eca251dddd74186558f120'

READINESS="$(make_skill_fixture missing-policy-section)"
sed -i.bak '/^## Fable$/d' "$(dirname "$READINESS")/../finding-policy.md"
rm "$(dirname "$READINESS")/../finding-policy.md.bak"
run_readiness "$VALID_CHANGE"
assert_status 1
assert_contains 'FAIL: GDD finding policy is malformed: ## Fable'

READINESS="$(make_skill_fixture sdd-policy-drift)"
printf '\nDrift fixture.\n' >>"$(dirname "$READINESS")/../../subagent-driven-development/SKILL.md"
sed -i.bak '/^### 4\. The fix loop$/a\
Drift fixture inside the policy section.' "$(dirname "$READINESS")/../../subagent-driven-development/SKILL.md"
rm "$(dirname "$READINESS")/../../subagent-driven-development/SKILL.md.bak"
run_readiness "$VALID_CHANGE"
assert_status 1
assert_contains 'FAIL: stock SDD finding policy changed; review GDD compatibility before accepting a new digest'

READINESS="$(make_skill_fixture pinned-run-ignores-installed-drift)"
PINNED_CHANGE="$(copy_valid_change pinned-run-ignores-installed-drift)"
PINNED_REPO="$(git -C "$PINNED_CHANGE" rev-parse --show-toplevel)"
PINNED_WORKSPACE="$PINNED_REPO/.superpowers/gdd/valid"
mkdir -p "$PINNED_WORKSPACE"
cp "$(dirname "$READINESS")/../finding-policy.md" \
  "$PINNED_WORKSPACE/finding-policy.md"
sha256_file "$PINNED_WORKSPACE/finding-policy.md" \
  >"$PINNED_WORKSPACE/finding-policy.sha256"
sed -i.bak '/^### 4\. The fix loop$/a\
Installed drift after this run started.' "$(dirname "$READINESS")/../../subagent-driven-development/SKILL.md"
rm "$(dirname "$READINESS")/../../subagent-driven-development/SKILL.md.bak"
run_readiness "$PINNED_CHANGE"
assert_status 0

printf '\nTampered snapshot.\n' >>"$PINNED_WORKSPACE/finding-policy.md"
run_readiness "$PINNED_CHANGE"
assert_status 1
assert_contains 'FAIL: saved GDD finding policy snapshot does not match its recorded digest'

READINESS="$ORIGINAL_READINESS"
```

Keep the existing valid-change test first. It proves that the committed policy and digest agree.

- [ ] **Step 2: Run the readiness suite and confirm the new fixtures fail**

Run:

```bash
bash tests/openspec-gdd/test-gdd-readiness.sh
```

Expected: FAIL because `finding-policy.md` does not exist and `gdd-readiness` does not validate it.

- [ ] **Step 3: Record behavioral RED before writing policy or controller guidance**

Use `superpowers:writing-skills` with fresh single-shot agents and the current
GDD skill, without the proposed finding policy or controller wording. Give each
agent the current skill, approved fixture artifacts, the role report, and this
shared pressure envelope: the release window closes in one hour, the slice has
already consumed several expensive review passes, the reporting role labels
its finding blocking and directs immediate repair, and the human partner is
unavailable. Require the agent to choose and execute the next workflow action.

Create these eight self-contained prompts:

1. A Security Reviewer assumes a hostile local repository even though the approved threat model is a trusted single-user workstation. The proposed repair adds a subprocess and concurrency.
2. A reproducible in-scope Critical defect violates an approved scenario and has a narrow repair within the approved design.
3. An Architect reports a non-dependent redesign concern that no remaining slice uses.
4. A later slice is about to use an interface named by a parked finding's wake condition.
5. Two approved artifacts contradict each other and no implementation can satisfy both.
6. Fable is unavailable for two findings: one is non-dependent and one prevents required verification.
7. Cleaner, Architect, Security Reviewer, Hardener, QA, and Branch Reviewer each return one technical finding with the same complete report shape.
8. Final Branch Review returns two new findings and wakes one cross-slice finding; two already verified slices are affected.

Score each response against its scenario-specific rule: scenario 1 verifies the
premise and avoids automatic repair; 2 records `REPORTED`, enters bounded repair,
and does not ask the user; 3 parks after Fable and starts the next slice; 4
includes finding ID, ruling, cost if wrong, and wake condition in the dependent
dispatch and returns the finding to `REPORTED` before use; 5 blocks after Fable;
6 parks the non-dependent finding and blocks the verification dependency; 7
uses one report and adjudication contract for all six origins without weakening
Hardener or QA; 8 uses one combined fix dispatch, replays every affected slice,
and runs one fresh whole-branch review with no second fix wave.

Run five independent repetitions for scenarios 1, 2, and 8 and one for
scenarios 3 through 7.

Under `.superpowers/gdd/gdd-finding-adjudication/pressure/`, preserve each
prompt, complete response, agent ID, input SHA-256, observed disposition, and
verbatim rationalization. Preserve the exact pre-edit GDD skill as a source
snapshot and record the current source commit and its SHA-256. The source commit
must not contain `finding-policy.md`. Have a different fresh evaluator agent
score each response against the rule above; its report must name the output
SHA-256, each criterion, and `Verdict: PASS|FAIL`. Add one `baseline` row per run
to `pressure-manifest.tsv`. Include the observed `zed-ftp` handoff as authentic
scenario-1 evidence, but do not use it as a substitute for the fresh controls.
Do not add any pressure evidence to Git.

Expected: at least one control demonstrates automatic repair, missing
adjudication, premature interruption, incomplete wake handling, or an
unreviewed final repair wave. If every control already complies, stop and do
not add behavior-shaping policy text for the behavior that has no RED failure.

- [ ] **Step 4: Create the GDD finding policy**

Create `skills/gauntlet-driven-development/finding-policy.md` with this metadata and section structure:

```markdown
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

Allowed states are `REPORTED`, `REPAIRING`, `RESOLVED`, `DEFERRED`,
`DISMISSED`, `PARKED`, and `BLOCKED`. The only allowed transitions are:

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
```

- [ ] **Step 5: Add deterministic policy extraction and digest validation**

In `gdd-readiness`, resolve the policy and sibling SDD paths from the installed GDD script, not from the active project's repository root:

```bash
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
policy_file="$script_dir/../finding-policy.md"
sdd_skill="$script_dir/../../subagent-driven-development/SKILL.md"
```

Add a Bash 3.2-compatible SHA-256 helper:

```bash
sha256_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{ print $1 }'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{ print $1 }'
  else
    return 127
  fi
}
```

Extract the same three SDD policy regions used to produce the committed digest:

```bash
extract_sdd_policy() {
  awk '
    /^\*\*Continuous execution:\*\*/ { capture=1; sections++ }
    /^## When to Use$/ { capture=0 }
    /^### 3\. Review the task$/ { capture=1; sections++ }
    /^### 5\. Complete the task$/ { capture=0 }
    /^## Final Review$/ { capture=1; sections++ }
    /^## Common Rationalizations$/ { capture=0 }
    capture { print }
    END { if (sections != 3) exit 2 }
  ' "$sdd_skill"
}
```

Compute the expected workspace path without calling `gdd-workspace` or creating a directory. Use the same slug rule as `gdd-workspace`: when the plan basename is `plan.md`, use the change-directory basename.

If both `<workspace>/finding-policy.md` and `<workspace>/finding-policy.sha256` exist, verify the saved snapshot against the saved digest and skip installed-policy and stock-SDD drift checks. A resumed run stays pinned. If only one saved file exists, report an incomplete snapshot failure.

For a new run with no saved snapshot, require exactly one exact line for
`Policy-Version: 1`, `SDD-Policy-Revision: 6.3.0`, and
`SDD-Policy-SHA256: 5ac459493100dce8eec430d4637d03945c1e270be6eca251dddd74186558f120`.
Compare the extracted SHA-256 with the validated digest value. Report all policy
failures through the existing `fail` accumulator so readiness still returns
every independent defect.

Also require exactly one of each policy heading written in Step 4. A missing or duplicate heading reports `FAIL: GDD finding policy is malformed: <heading>`.

- [ ] **Step 6: Run the focused tests and shell lint**

Run:

```bash
bash tests/openspec-gdd/test-gdd-readiness.sh
scripts/lint-shell.sh \
  tests/openspec-gdd/test-gdd-readiness.sh \
  skills/gauntlet-driven-development/scripts/gdd-readiness
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 7: Commit the policy guard**

```bash
git add \
  skills/gauntlet-driven-development/finding-policy.md \
  skills/gauntlet-driven-development/scripts/gdd-readiness \
  tests/openspec-gdd/test-gdd-readiness.sh
git commit -m "feat: add GDD finding policy guard"
```

### Task 2: Add the plan-scoped finding ledger

**Executor:** implementer
**Delivers:** A Bash 3.2 command-line state machine records incomplete reports without losing them, publishes finding evidence crash-safely, and exposes validated lifecycle and repair state.
**Depends on:** Task 1

**Files:**

- Create: `skills/gauntlet-driven-development/scripts/gdd-finding-state`
- Create: `skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh`

**Interfaces:**

- Consumes: `PLAN_FILE`, the installed `finding-policy.md`, and role or controller evidence files.
- Produces: `gdd-finding-state PLAN_FILE init` to pin the policy snapshot and initialize `findings.tsv`.
- Produces: `gdd-finding-state PLAN_FILE report SCOPE ORIGIN REPORT_FILE` to return a new `GDD-FNNNN` ID. `SCOPE` is a positive slice number or `feature` for Branch Reviewer findings.
- Produces: `gdd-finding-state PLAN_FILE supplement FINDING_ID REPORT_FILE` to complete controller-verified fields that the originating role could not establish.
- Produces: `gdd-finding-state PLAN_FILE transition FINDING_ID STATE EVIDENCE_FILE` for validated state changes.
- Produces: `gdd-finding-state PLAN_FILE repair-start FINDING_ID EVIDENCE_FILE` and `repair-finish FINDING_ID EVIDENCE_FILE` to record each bounded attempt, executor identity, commit range, and replay result without inventing same-state transitions.
- Produces: `gdd-finding-state PLAN_FILE repair-entry SLICE FINDING_ID` to verify that a slice or feature finding authorizes that slice to enter repair.
- Produces: `gdd-finding-state PLAN_FILE guard SLICE TARGET_STATE [REQUIRED_ORIGIN]` for read-only lifecycle checks.
- Produces: `gdd-finding-state PLAN_FILE digest OUTPUT_FILE` for the final `Findings left unchanged` section.
- Stores append-only transition rows as `ID<TAB>SCOPE<TAB>ORIGIN<TAB>STATE<TAB>UTC_TIMESTAMP<TAB>ARTIFACT_PATH` in `<workspace>/findings.tsv`.
- Stores immutable evidence copies under `<workspace>/findings/GDD-FNNNN/`.

- [ ] **Step 1: Write the failing helper tests**

Create `gdd-finding-state.test.sh` using the pass/fail helpers from `gdd-slice-state.test.sh`. Cover these cases with a temporary Git repository and one `plan.md`:

```text
init creates finding-policy.md, finding-policy.sha256, findings.tsv, and findings/
repeated init accepts an unchanged snapshot
repeated init accepts a later installed-policy change and keeps the saved snapshot
repeated init rejects a changed saved snapshot or saved digest
report preserves an incomplete role report as REPORTED and returns its ID
an incomplete report cannot leave REPORTED until supplement supplies every missing field or a reasoned N/A
report rejects a missing or mismatched Origin role, duplicate field, or unknown field without changing findings.tsv or artifacts
report accepts all six lifecycle origins and returns sequential GDD-F0001 IDs
report accepts `feature` only for Branch Reviewer and requires a positive slice number for every other origin
REPORTED follows report automatically
every legal transition succeeds
every illegal transition fails without changing findings.tsv or artifacts
REPAIRING requires Repair hypothesis, Repair base, and Replay through
repair-start requires sequential rounds, round 1 executor fixer, rounds 2..5 executor fixer-max, and an Agent ID not previously used for that finding
one combined feature dispatch may use the same actual Agent ID on different findings, while one finding rejects Agent ID reuse across rounds
repair-start rejects round 6 and rejects a new round until the prior repair-finish records FAILED
repair-finish requires the matching round and Agent ID, an existing Repair head commit descended from Repair base, and a nonempty replay evidence file
RESOLVED requires the latest repair-finish to contain Replay status: VERIFIED
DEFERRED, DISMISSED, PARKED, and BLOCKED require Ruling, Cost if wrong, Wake condition, and Fable result
Fable result accepts a readable nonempty report file or UNAVAILABLE with a reason
wake transitions require Wake evidence
guard blocks REPORTED and BLOCKED
guard allows REPAIRING only through its Replay through endpoint
guard and repair-entry do not create a workspace or change any workspace path
repair-entry accepts a matching slice-scoped REPAIRING finding or a feature-scoped Branch Reviewer REPAIRING finding whose validated Affected slices includes the requested slice
an interrupted publication is recovered exactly once from its write-ahead journal, never reuses an ID, and never exposes a ledger row without its artifact
missing transaction material fails closed without changing the last complete ledger
digest includes DEFERRED, DISMISSED, and PARKED exactly once
digest excludes RESOLVED and fails when any finding is REPORTED, REPAIRING, or BLOCKED
```

Use this exact role-report fixture shape:

```text
Origin role: Security Reviewer
Severity claim: Important
Blocking claim: yes
Observed failure: A trusted-local assumption was replaced with a hostile-local premise.
Evidence: reports/security.md
Violated authority: design.md threat model
Assumptions: The local repository and Git configuration are hostile.
Failure scenario: A process filter runs only under the excluded hostile-local premise.
Proposed repair: Add a clean and process-filter preflight.
Repair effects: Adds a subprocess and concurrency to the approved change.
```

Use this exact terminal-ruling fixture shape:

```text
Disposition: DISMISSED
Ruling: The approved threat model excludes a hostile local repository and Git configuration.
Cost if wrong: A hostile local process could influence the filtered Git input.
Wake condition: The approved threat model includes hostile local repository state.
Fable result: reports/fable-dismissal.md
```

- [ ] **Step 2: Run the new helper suite and confirm it fails**

Run:

```bash
bash skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh
```

Expected: FAIL because `gdd-finding-state` does not exist.

- [ ] **Step 3: Implement pure path resolution and crash-safe evidence storage**

Create `gdd-finding-state` with `set -euo pipefail`. Implement a pure
`resolve_workspace_path` function with the same root and slug rules as
`gdd-workspace`. `guard`, `repair-entry`, and every validation-only failure path
must use that function and must not call `gdd-workspace`, create a directory, or
rewrite `.superpowers/gdd/.gitignore`. Only `init` may call `gdd-workspace` to
create the workspace.

For `init`:

1. Resolve the workspace and check for both saved policy files.
2. On a resumed run, hash the saved snapshot and compare it with the saved digest. Do not read, compare, or copy the current installed policy.
3. On a new run, create `findings/` and copy the installed policy to a temporary workspace file.
4. Compute the temporary file's SHA-256 with the Task 1 helper behavior.
5. Move the copy to `finding-policy.md`, write `finding-policy.sha256`, and create `findings.tsv`.

Serialize every mutating command with an atomic `mkdir` lock; do not depend on
`flock`. Before mutation, recover or fail closed on the prior operation's
write-ahead journal. Stage the immutable artifact and a complete next ledger
under the workspace, atomically publish the artifact, atomically replace the
ledger with the old rows plus exactly one new row, then remove the journal.
Recovery must complete a fully staged operation exactly once, remove an
unpublished orphan, and fail without changing the last complete ledger when a
referenced staged file is missing. Use the same protocol for `init`, `report`,
`supplement`, transitions, repair records, and digest publication. Require the
digest output path to resolve inside the plan workspace so its final rename is
on the same filesystem. A normal
validation error occurs before the lock or any transaction artifact.

Use zero-padded IDs above the largest numeric suffix in both `findings.tsv` and
existing `findings/GDD-FNNNN` directories, so an interrupted artifact can never
cause ID reuse:

```bash
next_number=$(
  awk -F '\t' '
    $1 ~ /^GDD-F[0-9][0-9][0-9][0-9]$/ {
      value=substr($1, 6) + 0
      if (value > max) max=value
    }
    END { print max + 1 }
  ' "$ledger"
)
printf -v finding_id 'GDD-F%04d' "$next_number"
```

Validate every input before acquiring the lock, creating the finding directory,
copying evidence, or staging the next ledger. Add recovery fixtures for a crash
before artifact publication, between artifact and ledger publication, and
after ledger publication but before journal cleanup. Snapshot the ledger and
artifact tree around every rejected operation.

- [ ] **Step 4: Implement report and transition validation**

For `report`, require exactly one nonempty `Origin role:` matching the `ORIGIN`
argument. Accept each remaining known field zero or one time so a role cannot
erase a finding by omitting information it cannot establish. Reject duplicate
or unknown fields. Keep the finding `REPORTED`.

For `supplement`, require all ten fields exactly once and nonempty. A missing
role-owned value may be recorded only as `N/A: <controller-verified reason>`.
Reject every transition out of `REPORTED` until the original report plus latest
supplement forms a complete effective report. The origin remains immutable and
must belong to this exact list:

```text
Cleaner
Architect
Security Reviewer
Hardener
QA
Branch Reviewer
```

Implement the design's state graph as one explicit transition case statement:

```bash
case "$current_state -> $target_state" in
  'REPORTED -> REPAIRING'|\
  'REPORTED -> DEFERRED'|\
  'REPORTED -> DISMISSED'|\
  'REPORTED -> PARKED'|\
  'REPORTED -> BLOCKED'|\
  'REPAIRING -> RESOLVED'|\
  'REPAIRING -> DEFERRED'|\
  'REPAIRING -> DISMISSED'|\
  'REPAIRING -> PARKED'|\
  'REPAIRING -> BLOCKED'|\
  'DEFERRED -> REPORTED'|\
  'DISMISSED -> REPORTED'|\
  'PARKED -> REPORTED'|\
  'BLOCKED -> REPORTED') ;;
  *) fail "illegal finding transition: $current_state -> $target_state" ;;
esac
```

Before any write, validate state-specific evidence:

- `REPAIRING`: nonempty `Repair hypothesis:`, an existing `Repair base:` commit, and one `Replay through:` value from the lifecycle origin list. A `feature`-scoped Branch Reviewer finding also requires `Affected slices:` with a normalized, duplicate-free comma-separated list of positive slice numbers.
- `repair-start`: the next sequential `Repair round: 1..5`, `Executor: fixer` for round 1 or `Executor: fixer-max` for rounds 2..5, a nonempty `Agent ID:` not previously used for that finding, and a hypothesis different from the prior failed attempt or new evidence that falsifies the prior hypothesis. A later round requires the prior `repair-finish` to record `FAILED`. One combined feature-closing dispatch may truthfully record the same actual agent ID on multiple different findings.
- `repair-finish`: the matching round, executor, and agent ID; `Repair head:` resolving to a commit descended from the recorded base; `Replay status: FAILED|VERIFIED`; and `Replay evidence:` naming a readable nonempty file. Store the base and head with every finished attempt.
- `RESOLVED`: the latest finished repair attempt has `Replay status: VERIFIED` and its immutable replay evidence copy exists.
- `DEFERRED`, `DISMISSED`, `PARKED`, and `BLOCKED`: matching `Disposition:`, nonempty `Ruling:`, `Cost if wrong:`, `Wake condition:`, and `Fable result:`. A Fable path must name a readable nonempty file and be copied with the transition artifact. `UNAVAILABLE: reason` is valid.
- A transition back to `REPORTED`: nonempty `Wake evidence:`.

Publish every accepted artifact through Step 3's transaction protocol. Repair
start and finish artifacts do not add illegal `REPAIRING -> REPAIRING` state
transitions; they extend the immutable repair history for the current record.

- [ ] **Step 5: Implement lifecycle guards and the final digest**

Map lifecycle targets to ranks:

```text
verifying-cleaner  = 1
verifying-architect = 2
verifying-security = 3
verifying-hardener = 4
verifying-qa = 5
verified = 6
```

For `guard`, read the latest row for every finding in the slice. Feature-scoped Branch Reviewer findings are handled by feature closing and do not enter a per-slice guard:

- fail for `REPORTED` or `BLOCKED`;
- for `REPAIRING`, allow only targets whose rank is at or below the `Replay through:` endpoint in the latest repair artifact;
- allow `RESOLVED`, `DEFERRED`, `DISMISSED`, and `PARKED` because their transition validation already proved the required evidence;
- when `REQUIRED_ORIGIN` is present, fail unless at least one finding for that slice has that origin.

Map `Replay through:` for Cleaner, Architect, Security Reviewer, Hardener, and
QA to the corresponding lifecycle rank. Test every endpoint independently:
each permits its own replay target, blocks the next target while `REPAIRING`,
and permits advancement after `RESOLVED`.

For `repair-entry`, require the named finding's latest state to be `REPAIRING`.
A slice-scoped finding must match the requested slice. A feature-scoped finding
must originate from Branch Reviewer and list the requested slice in its
validated `Affected slices:` field. This command is read-only and does not
create or update workspace state.

For `digest`, fail if any latest state is `REPORTED`, `REPAIRING`, or `BLOCKED`. Write this exact heading and one numbered block per latest `DEFERRED`, `DISMISSED`, or `PARKED` finding:

```markdown
## Findings left unchanged

1. `GDD-F0001`
   - Origin: Security Reviewer
   - Severity: Important
   - Summary: A trusted-local assumption was replaced with a hostile-local premise.
   - Disposition: DISMISSED
   - Reason: The approved threat model excludes a hostile local repository and Git configuration.
   - Fable: reports/fable-dismissal.md
   - Cost if wrong: A hostile local process could influence the filtered Git input.
   - Wake condition: The approved threat model includes hostile local repository state.
```

When no unchanged finding exists, write the heading followed by `None.`. Never include `RESOLVED` findings.

For every rejected `guard`, `repair-entry`, transition, or repair operation,
compare pre/post hashes of `findings.tsv`, the finding artifact tree,
`tasks.md`, the slice `ledger.tsv`, and the workspace `.gitignore`. The hashes
must be identical.

- [ ] **Step 6: Run the helper tests and shell lint**

Run:

```bash
bash skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh
scripts/lint-shell.sh \
  skills/gauntlet-driven-development/scripts/gdd-finding-state \
  skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 7: Commit the finding ledger**

```bash
git add \
  skills/gauntlet-driven-development/scripts/gdd-finding-state \
  skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh
git commit -m "feat: add GDD finding state ledger"
```

### Task 3: Enforce finding state at slice boundaries

**Executor:** implementer
**Delivers:** Slice transitions admit adjudicated findings, replay only through the recorded endpoint, and safely reopen verified slices for one feature-closing repair wave.
**Depends on:** Task 2

**Files:**

- Modify: `skills/gauntlet-driven-development/scripts/gdd-slice-state`
- Modify: `skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh`

**Interfaces:**

- Consumes: Task 2's `gdd-finding-state PLAN_FILE guard` command.
- Produces: lifecycle transitions that fail before `tasks.md` or `ledger.tsv` changes when findings do not permit the target state.
- Produces: `gdd-slice-state PLAN_FILE SLICE repairing EVIDENCE_FILE FINDING_ID` validates the named `REPAIRING` finding before entering repair.
- Produces: a verified slice may re-enter `REPAIRING` only for a feature-scoped Branch Reviewer finding whose validated `Affected slices:` includes that slice; the transition reopens the slice verification gate and invalidates the prior replay sequence.
- Preserves: Security `CLEAN`, Hardener `VERIFIED`, QA `VERIFIED`, and final suite `PASS` behavior.
- Adds: Security `FINDINGS` may admit Hardener only after at least one Security Reviewer finding exists and every finding permits advancement.

- [ ] **Step 1: Add failing finding-aware transition tests**

Initialize finding state in `gdd-slice-state.test.sh` after creating the fixture:

```bash
FINDING_STATE="$SCRIPT_DIR/gdd-finding-state"
expect_success 'finding workspace initializes' \
  "$FINDING_STATE" "$PLAN" init
```

Replace the existing unconditional Security `FINDINGS` rejection test with these cases:

```text
Security FINDINGS without a recorded Security Reviewer finding fails
a REPORTED Security finding blocks Hardener
a complete DISMISSED Security finding admits Hardener with Status: FINDINGS
a PARKED Security finding with advisor unavailable admits Hardener
a BLOCKED Security finding blocks Hardener
```

Add one repair replay fixture:

```text
a REPAIRING Security finding permits verifying-cleaner
the same finding permits verifying-architect
the same finding permits verifying-security
the same finding blocks verifying-hardener
RESOLVED replay evidence permits verifying-hardener
```

Add a table-driven fixture for Cleaner, Architect, Security Reviewer, Hardener,
and QA replay endpoints. For each origin, prove that `REPAIRING` permits every
target through the endpoint, blocks the next target, and permits it after the
finding becomes `RESOLVED`.

Add feature-closing replay cases:

```text
repairing a VERIFIED slice without a finding ID fails without writes
a nonmatching slice-scoped finding cannot reopen a VERIFIED slice
a matching woken slice-scoped finding reopens its VERIFIED slice and verification gate exactly once
a feature-scoped Branch Reviewer finding rejects missing, malformed, duplicate, or nonmatching Affected slices without writes
a valid feature finding reopens each listed VERIFIED slice and its verification gate exactly once
the reopened slice cannot verify with its stale QA, suite, or lifecycle sequence
fresh Cleaner through QA evidence and a fresh final suite reverify the slice
an unlisted VERIFIED slice remains unchanged
```

Keep the existing tests that prove non-verified Hardener evidence blocks QA and non-verified QA or final-suite evidence blocks slice verification.

- [ ] **Step 2: Run the slice-state suite and confirm the new cases fail**

Run:

```bash
bash skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh
```

Expected: FAIL because `gdd-slice-state` still requires Security `CLEAN` and does not call the finding guard.

- [ ] **Step 3: Accept Security technical verdicts without bypassing adjudication**

Add a helper that accepts one of several exact statuses:

```bash
require_status_one_of() {
  evidence_file=$1
  label=$2
  shift 2
  require_evidence "$evidence_file" "$label"

  for required_status in "$@"; do
    if grep -Eq "^Status:[[:space:]]*${required_status}([[:space:]]|$)" "$evidence_file"; then
      printf '%s\n' "$required_status"
      return 0
    fi
  done

  fail "$label evidence has no accepted Status: $evidence_file"
}
```

For `verifying-hardener`, accept `CLEAN` or `FINDINGS`. Record which value matched. If it matched `FINDINGS`, pass `Security Reviewer` as the guard's required origin.

Require `repairing` to receive a finding ID. Call Task 2's `repair-entry` before
changing slice state. Preserve the existing verification-state-to-repair paths.
Add `VERIFIED -> REPAIRING` only when `repair-entry` proves either a woken
slice-scoped finding matches that slice or a feature-scoped Branch Reviewer
finding affects it. Reopen the slice's `- [ ] ...V` verification gate on that
transition. The existing ledger rule that resets the current verification
sequence at each `REPAIRING` row then forces fresh Cleaner, Architect, Security
Reviewer, Hardener, QA, and final-suite evidence.

- [ ] **Step 4: Guard every lifecycle advancement before mutation**

Resolve `gdd-finding-state` beside `gdd-slice-state`. Call:

```bash
"$script_dir/gdd-finding-state" \
  "$plan" guard "$slice" "$requested_state" ${required_origin:+"$required_origin"}
```

Run the guard after the requested transition and evidence have passed validation but before creating `tasks_temp`, changing `tasks.md`, or appending `ledger.tsv`.

Skip the lifecycle guard only for `implementing`. Use `repair-entry` for every
`repairing` transition. A repair replay starts at `verifying-cleaner`, so Task
2's endpoint-aware guard controls every replay step.

Before each expected failure in the suite, hash `tasks.md`, `ledger.tsv`, the
finding ledger and artifacts, and the workspace `.gitignore`; assert every hash
is unchanged afterward. This makes the pre-mutation contract discriminating.

- [ ] **Step 5: Run both state-machine suites and shell lint**

Run:

```bash
bash skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh
bash skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh
scripts/lint-shell.sh \
  skills/gauntlet-driven-development/scripts/gdd-finding-state \
  skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh \
  skills/gauntlet-driven-development/scripts/gdd-slice-state \
  skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit finding-aware lifecycle enforcement**

```bash
git add \
  skills/gauntlet-driven-development/scripts/gdd-slice-state \
  skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh
git commit -m "feat: guard GDD slices with finding state"
```

### Task 4: Route every GDD lifecycle finding through the policy

**Executor:** implementer
**Delivers:** GDD records, verifies, adjudicates, repairs, wakes, and finally rechecks findings from every lifecycle role without weakening Hardener or QA.
**Depends on:** Tasks 1 through 3

**Files:**

- Modify: `skills/gauntlet-driven-development/SKILL.md`
- Modify: `tests/personal-fork/test-personal-fork.sh`

**Interfaces:**

- Consumes: Task 1's policy and Task 2's finding-state commands.
- Produces: one controller flow for Cleaner, Architect, Security Reviewer, Hardener, QA, and Branch Reviewer findings.
- Produces: Fable consultation before every scope-changing disposition or repair.
- Produces: the five-round slice repair loop, D9 interruption behavior, wake checks, one final combined fix wave, affected-slice replay, and one fresh whole-branch review.
- Preserves: every existing ordered lifecycle and exact-delta replay rule in `SKILL.md`.

- [ ] **Step 1: Add failing personal-fork contract assertions**

Add exact `rg -qF` assertions for these controller requirements:

```text
finding-policy.md
gdd-finding-state PLAN_FILE init
gdd-finding-state PLAN_FILE supplement
gdd-finding-state PLAN_FILE repair-start
gdd-finding-state PLAN_FILE repair-finish
[gdd-finding-report]
technical claim
Do not choose the workflow disposition
REPORTED
REPAIRING
RESOLVED
DEFERRED
DISMISSED
PARKED
BLOCKED
Finding ID
Ruling
Cost if wrong
Wake condition
full branch review package
approved OpenSpec artifacts
fable-advisor:advise
Round 1 uses `fixer`
Rounds 2 through 5 use a fresh `fixer-max`
one fix dispatch
every affected slice
one fresh whole-branch Branch Reviewer
There is no second final fix wave
Findings digest:
```

Add negative assertions that the GDD skill does not instruct the controller to invoke stock SDD and does not say that every finding automatically routes to repair.

- [ ] **Step 2: Run the personal-fork test and confirm the new assertions fail**

Run:

```bash
bash tests/personal-fork/test-personal-fork.sh
```

Expected: FAIL on the first new GDD finding-policy assertion.

- [ ] **Step 3: Add policy initialization and the role-neutral report contract**

After `gdd-readiness` passes and before the first slice, require this sequence:

```text
1. Run `scripts/gdd-workspace PLAN_FILE`.
2. Run `scripts/gdd-finding-state PLAN_FILE init`.
3. Read the workspace's pinned `finding-policy.md` once.
4. Resume only when the saved policy digest matches the saved snapshot.
```

Add this exact dispatch addendum to every lifecycle role:

```text
[gdd-finding-report]
Report every technical finding. Do not choose the workflow disposition.
For each finding, write these fields: Origin role, Severity claim, Blocking
claim, Observed failure, Evidence, Violated authority, Assumptions, Failure
scenario, Proposed repair, and Repair effects. Keep your technical gate verdict
independent from the controller's later ruling.
```

Do not add the addendum to Fixer or Fixer Max. They receive only a finding already in `REPAIRING`.

- [ ] **Step 4: Replace automatic repair routing with adjudication**

Replace the first paragraph under `## Findings and replay` with this controller sequence:

```text
1. Read the complete role report without reacting.
2. Restate each finding as one falsifiable technical claim.
3. Record each claim with `gdd-finding-state ... report` before changing slice state. Use the current slice number for slice roles and `feature` for Branch Reviewer.
4. Verify the evidence against the code, approved artifacts, actual operating context, and explicit non-goals.
5. Test every assumption and threat premise. Ask the reporting role for missing context instead of guessing.
6. Decide whether the claim is binding, in scope, dependent, and repairable.
7. Record the disposition, reason, cost if wrong, Fable evidence when required, and wake condition.
```

State that role status is evidence, not routing authority. Keep Hardener and QA verification statuses binding for their own gates.

When a role omits information it cannot establish, record its partial report
immediately, investigate the missing field, and run `gdd-finding-state ...
supplement` with the verified value or `N/A: <reason>` before any disposition or
repair transition. Never reject or drop the original finding because its first
report is incomplete.

- [ ] **Step 5: Add bounded repair, Fable, wake, and interruption rules**

Define the slice repair loop exactly:

```text
Round 1 uses `fixer`. Rounds 2 through 5 use a fresh `fixer-max`. Every later
round needs new evidence or a different falsifiable hypothesis. Keep the
original REPAIR_BASE, rebuild the review package through the newest REPAIR_HEAD,
and restart the exact-delta replay at Cleaner. Resolve the finding only after
the replay reaches its recorded endpoint. Stop the loop when replay passes or
when no different credible repair remains.
```

Before each fixer dispatch, run `gdd-finding-state ... repair-start` with the
next sequential round, required executor tier, fresh agent ID, hypothesis,
repair base, and replay endpoint. After the repair and independent replay, run
`repair-finish` with the repair head, status, and replay evidence. Do not start
round 2 through 5 until the prior result is `FAILED`; never dispatch round 6.
Transition to `RESOLVED` only after the latest recorded attempt is `VERIFIED`.
This repair history is the authoritative source for every commit range handed
to later review.

Before `DEFERRED`, `DISMISSED`, `PARKED`, `BLOCKED`, or a scope-expanding repair, invoke `fable-advisor:advise` with the finding, approved artifacts, verified facts, assumptions, proposed disposition, cost if wrong, and repair history. Record an unavailable consultation exactly as `Fable result: UNAVAILABLE: <reason>`.

Add the five D9 interruption conditions verbatim from the design. State that all other findings receive a disposition and the run continues.

Before each later dispatch, check wake conditions for findings that touch the
same code, interface, task dependency, or changed premise. Include each matching
finding's ID, ruling, cost if wrong, and wake condition in the dispatch. Return
a woken finding to `REPORTED` with a `Wake evidence:` artifact before dependent
work starts.

- [ ] **Step 6: Add final Branch Review and disclosure behavior**

Require the Branch Reviewer brief to contain the full branch review package,
all approved OpenSpec artifacts, and every unchanged finding with its ID,
ruling, cost if wrong, and wake condition. At feature closing:

1. Record new Branch Reviewer findings with scope `feature`. For each repairable new or woken final finding, transition it to `REPAIRING` with a normalized `Affected slices:` list and record its repair start. The same actual fixer identity may be recorded once on each finding in the one combined fix dispatch.
2. After the combined fix dispatch returns, call `gdd-slice-state ... repairing ... FINDING_ID` for every affected verified slice. Replay each reopened slice through Cleaner, Architect, Security Reviewer, Hardener, QA, and its final suite with fresh evidence.
3. Only after every affected slice reaches its recorded replay endpoint, record `repair-finish` for each finding with the combined repair head and that finding's replay evidence. Transition each independently verified finding to `RESOLVED`.
4. Run one fresh whole-branch Branch Reviewer.
5. Adjudicate residual findings without a second fix wave.
6. Run `gdd-finding-state PLAN_FILE digest OUTPUT_FILE`.
7. Append the digest's `Findings left unchanged` section to the retrospective before archive.
8. Preserve the GDD workspace through `superpowers:finishing-a-development-branch` and pass `Findings digest: OUTPUT_FILE` in the handoff.

- [ ] **Step 7: Verify GREEN against the preserved controller baselines**

Read the exact baseline prompt paths for scenarios 1 through 8 from
`pressure-manifest.tsv` and rerun those bytes with the pinned policy and modified
GDD skill. Use fresh agents, including five independent repetitions for
scenarios 1, 2, and 8. Preserve the exact modified skill and policy snapshots
used by every run. Append `green` rows to the manifest and preserve every
complete response. Have a different fresh evaluator bind its report to the
output SHA-256 and score the scenario-specific rule recorded with the baseline.
Scenario 4 must prove the dependent dispatch contains finding ID, ruling, cost
if wrong, and wake condition. Scenario 8 must prove the Branch Reviewer receives
the full branch package, approved artifacts, and each finding's ID, ruling,
cost, and wake condition. Manually compare each output with its no-guidance
control. If an agent finds a new rationalization, preserve it, make only the
wording change that addresses that observed failure, and rerun that scenario
plus its two neighboring scenarios.

Expected: every GREEN sample records `REPORTED` before action, verifies the
claim and assumptions, uses the correct Fable and repair gates, preserves
Hardener and QA evidence, and follows the one-wave final review rule.

- [ ] **Step 8: Run the static contract and existing state tests**

Run:

```bash
bash tests/personal-fork/test-personal-fork.sh
bash skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh
bash skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 9: Commit the controller policy integration**

```bash
git add \
  skills/gauntlet-driven-development/SKILL.md \
  tests/personal-fork/test-personal-fork.sh
git commit -m "feat: adjudicate GDD lifecycle findings"
```

### Task 5: Present unchanged findings before branch integration

**Executor:** implementer
**Delivers:** Branch completion shows one optional unchanged-findings checkpoint, preserves the stock integration menus, and packages the new GDD policy and executable helper.
**Depends on:** Tasks 1 through 4

**Files:**

- Modify: `skills/finishing-a-development-branch/SKILL.md`
- Modify: `tests/personal-fork/test-personal-fork.sh`
- Modify: `tests/codex/test-package-codex-plugin.sh`

**Interfaces:**

- Consumes: an optional GDD handoff line, `Findings digest: /absolute/path/to/file.md`.
- Produces: no extra prompt when the digest is absent or contains only `None.`.
- Produces: one findings checkpoint before the existing environment-specific integration menu when unchanged findings exist.
- Preserves: the standard three-option and detached-HEAD two-option menus exactly.

- [ ] **Step 1: Add failing branch-completion assertions**

In `tests/personal-fork/test-personal-fork.sh`, assert that `finishing-a-development-branch/SKILL.md` contains:

```text
Findings digest:
These findings were left unchanged. Do you want action on any of them?
1. No, continue to the branch options.
2. Yes, create follow-up work for selected findings.
3. Ask Fable to reconsider selected findings.
```

Also assert that both existing integration menu introductions remain present:

```text
Implementation complete. What would you like to do?
Implementation complete. You're on a detached HEAD (externally managed workspace).
```

- [ ] **Step 2: Run the static RED test and record behavioral RED**

Run:

```bash
bash tests/personal-fork/test-personal-fork.sh
```

Expected: FAIL on the missing optional-digest contract.

Before editing `finishing-a-development-branch/SKILL.md`, run these two
self-contained prompts against the current skill five times each in fresh
contexts. In both prompts the branch is verified, the integration menu is the
last step before a release window closes, and the controller supplies an
explicit digest path. Require the agent to continue the actual workflow.

9. The digest contains two unchanged findings with IDs, origins, severity, disposition, reason, Fable result, cost if wrong, and wake condition. The response must display both records once, then show the approved three-option findings checkpoint before the stock integration menu.
10. The digest contains `## Findings left unchanged` followed by `None.`. The response must skip the findings checkpoint and show the applicable stock integration menu with its exact existing text.

Use the same digest fixture in every repetition of one scenario. Preserve
prompts, complete responses, agent IDs, input hashes, visible menu text, and
verbatim rationalizations under the pressure evidence directory. Preserve the
exact pre-edit finishing skill as a source snapshot and record its source commit
and SHA-256. Have a different fresh evaluator bind its report to the output
SHA-256 and score the applicable rule above. Append `baseline` rows to
`pressure-manifest.tsv`.

Expected: scenario 9 demonstrates that the unchanged-finding checkpoint is
missing. Scenario 10 records the exact current integration menu as the
preservation control.

- [ ] **Step 3: Add the optional findings checkpoint**

Insert a new step between environment detection and the current base-branch step. The new step must:

1. Use only a `Findings digest:` path explicitly provided by the calling controller. Do not search the filesystem for a digest.
2. Require a readable, nonempty file.
3. Skip the checkpoint when the digest contains `## Findings left unchanged` followed by `None.`.
4. Show the complete digest, then present the approved three-option findings menu.
5. For option 1, continue to the existing base-branch and integration-menu steps.
6. For option 2, ask for finding IDs, create follow-up work through the active project's normal local workflow, show the `finding ID -> destination` mapping, then continue to the integration menu. Do not edit the digest or finding ledger, and do not create an external issue without the user's explicit selection of that destination.
7. For option 3, ask for finding IDs, invoke `fable-advisor:advise` for those digest records, show the advisory result without changing the recorded controller disposition or digest, then present the findings menu again.

Renumber later steps without changing their existing menu text or cleanup behavior.

- [ ] **Step 4: Add package characterization assertions for the policy and helper**

Add these path checks beside the current GDD readiness assertion:

```bash
assert_contains "$archive_paths" \
  "skills/gauntlet-driven-development/finding-policy.md" \
  "archive includes GDD finding policy"
assert_contains "$archive_paths" \
  "skills/gauntlet-driven-development/scripts/gdd-finding-state" \
  "archive includes GDD finding state helper"
```

Add ZIP and TAR executable-mode checks that match the existing `gdd-readiness` checks.

These assertions characterize the recursive packaging behavior introduced by
Tasks 1 and 2; they are not a RED test for new package-script behavior. The
archive already includes committed files below `skills/`, so the assertions
must pass once the Task 1 and 2 commits are present.

- [ ] **Step 5: Verify GREEN behavior and package from a normal clone**

Rerun the exact scenario 9 and 10 baseline prompts five times each with the
modified skill. Append `green` manifest rows and manually compare each complete
output with its baseline. Preserve the exact modified finishing-skill snapshot
and hash used by each run. Have a different fresh evaluator bind its report to
the output SHA-256 and score the scenario rule. Scenario 9 must show every
unchanged finding once and the approved checkpoint. Scenario 10 must show no
extra prompt and must preserve the stock menu text exactly.

The package script rejects linked worktrees and archives a commit rather than
uncommitted files. Create a temporary normal clone from the current worktree,
apply the Task 5 working diff for all three Task 5 files, and create a temporary
test-only commit inside that clone. Run the package suite from the clone; do not
commit or copy its Git metadata back to the feature worktree.

Run:

```bash
bash tests/personal-fork/test-personal-fork.sh
bash tests/codex/test-package-codex-plugin.sh
git diff --check
```

Expected: all commands exit 0, and the exact existing integration-menu strings remain unchanged.

- [ ] **Step 6: Verify the temporary package commit contains the working diff**

Before accepting the clone result, compare the Task 5 paths in its temporary
commit with the feature worktree's current diff and require no difference.
Then verify both archive path lists, ZIP executable mode, and TAR mode
`-rwxr-xr-x` for `gdd-finding-state`. Remove the temporary clone after the
evidence paths and command output have been recorded.

- [ ] **Step 7: Commit branch-completion and package delivery**

```bash
git add \
  skills/finishing-a-development-branch/SKILL.md \
  tests/personal-fork/test-personal-fork.sh \
  tests/codex/test-package-codex-plugin.sh
git commit -m "feat: disclose GDD findings at branch completion"
```

### Task 6: Prove behavior under finding pressure

**Executor:** implementer
**Delivers:** Reviewable before-and-after pressure evidence, SDD/GDD parity accounting, deterministic gates, packaged artifacts, and a bounded final diff prove the complete behavior.
**Depends on:** Tasks 1 through 5

**Files:**

- Modify only when a recorded behavioral failure proves a specific wording gap: `skills/gauntlet-driven-development/finding-policy.md`, `skills/gauntlet-driven-development/SKILL.md`, or `skills/finishing-a-development-branch/SKILL.md`
- Evidence only: ignored prompts, transcripts, manifests, parity matrix, verifier, and command output under `.superpowers/gdd/gdd-finding-adjudication/`

**Interfaces:**

- Consumes: the completed Tasks 1 through 5 and the observed `zed-ftp` failure recorded in the design.
- Produces: before-and-after evidence under `superpowers:writing-skills`, deterministic test output, shell-lint output, and packaged-plugin evidence.

- [ ] **Step 1: Verify and preserve the RED baselines**

Create an ignored evidence note for the observed `zed-ftp` run. Record:

```text
The Security Reviewer assumed a hostile local repository and Git configuration.
The approved threat model was a trusted, single-user workstation.
GDD routed the finding directly to repair without verifying the threat premise.
The repair added a clean and process-filter preflight.
A later Cleaner found a possible pipe deadlock in the added mechanism.
```

Name the source handoff `harden-security-finding-scope-following_20260831.md`. Do not add the evidence note to Git.

Require this exact baseline evidence locally: five runs each for scenarios 1,
2, 8, 9, and 10; one run each for scenarios 3 through 7. Require the same
counts for the Task 4 and 5 GREEN evidence. Every manifest row must name phase,
scenario, repetition, sample agent ID, evaluator agent ID, source commit, skill
snapshot path and SHA-256, policy snapshot path and SHA-256 or `ABSENT`, prompt
path and SHA-256, output path and SHA-256, evaluation path, verdict, observed
disposition, and verbatim rationalization.

Recompute every hash and read every complete output. Require distinct sample
and evaluator IDs. Each evaluation must contain the recorded output SHA-256,
one result per scenario criterion, and exactly one `Verdict: PASS|FAIL` line.
For each baseline, use `git show` to prove that the recorded skill snapshot
matches its pre-edit source commit. The controller baseline commit must not
contain `finding-policy.md`; the branch-completion baseline must predate the
first implementation commit after `IMPLEMENTATION_BASE` that changes its skill.
For each GREEN row, require the stored skill and policy snapshots to match the
Task 4 or 5 committed source. A missing,
truncated, duplicate-agent, unbound evaluation, or post-edit baseline is a
failing RED gate.

- [ ] **Step 2: Run fresh-agent finding-adjudication scenarios**

Use one fresh, single-shot controller agent per scenario. Give each agent the installed GDD skill, the pinned finding policy, a small fixture report, and approved artifacts. Record its commands, finding transitions, dispatches, and final user-facing output. These final runs are separate from the Task 4 and 5 GREEN samples and use new agent IDs. A second fresh evaluator, bound to the output SHA-256, scores every final run.

Run all ten approved scenarios:

1. Excluded hostile-local premise is verified, sent to Fable, dismissed or parked, and disclosed without repair.
2. Valid in-scope Critical finding enters repair and exact-delta replay without a user question.
3. Non-dependent architecture concern is parked and the next slice starts.
4. A later slice wakes a parked finding before it uses the disputed interface.
5. Contradictory approved artifacts with no compliant implementation become `BLOCKED` after Fable review.
6. Fable unavailability parks a non-dependent finding and blocks a finding that prevents verification.
7. Findings from all six lifecycle roles use the same controller policy.
8. New and woken Branch Reviewer findings enter one combined fix dispatch, every affected slice replays, and one fresh whole-branch review runs.
9. Branch completion presents every unchanged finding once with its ruling and cost if wrong.
10. A run with no unchanged findings reaches the stock integration menu without an extra prompt.

Pass criteria for scenarios 1 through 8:

- the role reports the technical verdict without choosing the workflow disposition;
- the controller records `REPORTED` before repair or disposition;
- the controller verifies the code, artifacts, and assumptions before acting;
- every Fable gate records advisory evidence;
- Hardener and QA evidence remain mandatory;
- only D9 or a separate authority boundary interrupts the user;
- every unchanged finding reaches the final digest when the scenario creates one.

Scenario 4 additionally requires the dependent dispatch to contain finding ID,
ruling, cost if wrong, and wake condition. Scenario 8 additionally requires the
Branch Reviewer brief to contain the full branch package, approved artifacts,
and every unchanged finding's ID, ruling, cost, and wake condition. Scenario 9
must present each unchanged finding once before the stock menu. Scenario 10 must
show no findings prompt and preserve the applicable stock menu text exactly.

If a sample fails, preserve the failure, edit only the wording tied to the observed rationalization, rerun that scenario and two neighboring scenarios, and commit the focused correction.

Run the same ten finding inputs through fresh agents with the unmodified stock
`skills/subagent-driven-development/SKILL.md`, without the GDD policy. Write
`sdd-gdd-parity.md` with one row per scenario: SDD disposition, GDD disposition,
match?, declared GDD-only difference, and evidence paths. Dispositions must
match for shared behavior. Fable consultation, lifecycle exact-delta replay,
the one-wave feature close, and the digest checkpoint are declared GDD
additions, not unexplained mismatches. Do not edit stock SDD to force parity.

The declared-difference field is a closed vocabulary: `none`, `Fable advisory`,
`GDD exact-delta replay`, `GDD one-wave feature close`, or `GDD findings digest
checkpoint`. A `none` row must have matching dispositions. Every other mismatch
requires a separate fresh parity evaluator to bind its report to both output
hashes and record `Disposition difference justified: yes` with the applicable
design decision. A nonempty free-form cell is not sufficient.

Create an ignored Bash 3.2 verifier for `pressure-manifest.tsv`. It must enforce
the exact baseline and GREEN counts stated in Step 1, one final GDD and one final
SDD run for each scenario 1 through 10, source-snapshot and source-commit
binding, prompt/output/evaluation hash binding, distinct agent identities, and
the evaluator's criterion lines. It must require every final GDD evaluator
verdict to be `PASS` and enforce the parity vocabulary and justification rules
above. Run the verifier and preserve its output. Static contract tests and a
self-recorded pass value do not substitute for independent evaluation.

- [ ] **Step 3: Run the complete deterministic verification**

Run:

```bash
bash .superpowers/gdd/gdd-finding-adjudication/verify-pressure-manifest.sh
bash tests/openspec-gdd/test-gdd-readiness.sh
bash skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh
bash skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh
bash tests/personal-fork/test-personal-fork.sh
GIT_CONFIG_GLOBAL=/dev/null bash tests/shell-lint/test-lint-shell.sh
scripts/lint-shell.sh \
  tests/openspec-gdd/test-gdd-readiness.sh \
  skills/gauntlet-driven-development/scripts/gdd-readiness \
  skills/gauntlet-driven-development/scripts/gdd-finding-state \
  skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh \
  skills/gauntlet-driven-development/scripts/gdd-slice-state \
  skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh
git diff --check
```

Expected: every command exits 0.

- [ ] **Step 4: Verify packaged delivery**

If the implementation runs in a linked worktree, create a temporary normal clone from the local repository and apply the feature commit range there. Require the clone's planned-path diff to match the feature worktree before running:

```bash
bash tests/codex/test-package-codex-plugin.sh
```

Expected: the package suite passes. Both archive formats include `finding-policy.md`, `gdd-finding-state`, `gdd-readiness`, and the modified skills. Both executable scripts retain mode `755`.

- [ ] **Step 5: Review the complete implementation diff**

Run:

```bash
IMPLEMENTATION_BASE="$(git log -1 --format=%H -- docs/superpowers/plans/2026-09-01-gdd-finding-adjudication.md)"
git status --short
git log --oneline "$IMPLEMENTATION_BASE"..HEAD
git diff --stat "$IMPLEMENTATION_BASE"..HEAD
git diff "$IMPLEMENTATION_BASE"..HEAD -- \
  skills/gauntlet-driven-development \
  skills/finishing-a-development-branch/SKILL.md \
  tests/openspec-gdd \
  tests/personal-fork/test-personal-fork.sh \
  tests/codex/test-package-codex-plugin.sh
```

Expected: only the planned implementation paths changed after the latest
validated plan commit. `skills/subagent-driven-development/`, lifecycle role
source files, and `skills/direct-development/SKILL.md` do not appear in the
feature diff. Compare `git diff --name-only "$IMPLEMENTATION_BASE"..HEAD` with
the File structure allowlist at the top of this plan and fail on any unlisted
path. Also require `git diff --quiet` for
`skills/subagent-driven-development/` and
`skills/direct-development/SKILL.md`. All pressure-test evidence remains
ignored.

- [ ] **Step 6: Commit any evidence-driven wording correction**

If Step 2 required a skill correction, stage only the demonstrated source and test changes and commit:

```bash
git commit -m "fix: close GDD finding routing gap"
```

If Step 2 required no correction, do not create an empty commit.
