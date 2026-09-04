# GDD review ceremony implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the per-slice Security Reviewer stage with a Task Reviewer review stage and bounded fix rounds, move security review to feature closing, and record every advisor consultation in the finding ledger.

**Architecture:** Three bash scripts under `skills/gauntlet-driven-development/scripts/` form the engine. `gdd-workflow-state` owns the append-only event journal, the static obligation table, and the reducer that decides which obligation is READY next. `gdd-finding-state` validates finding evidence and calls the engine. `gdd-slice-state` projects slice states into `tasks.md`. Each script has a sibling `*.test.sh` that is the executable contract. Policy text, the skill body, and the agent definitions in the claude-config repo describe the same ceremony in prose.

**Tech Stack:** bash 3.2 compatible scripts (macOS `/bin/bash`), awk, git, shell test harnesses, python `tomllib` parity test, TOML agent adapters for Codex.

**Spec:** `docs/superpowers/specs/2026-09-03-gdd-review-ceremony-design.md` (decisions D1 through D16). Read it before any task.

## Global constraints

- Workflow format version is `2`. `validate_format_version` accepts only `2`. `initialize_workflow` writes `2`. `format-version` prints `2`. A version 1 workflow fails with `workflow format version is unknown: 1`.
- Finding policy header is `Policy-Version: 2`. `gdd-readiness` sets `EXPECTED_POLICY_VERSION='Policy-Version: 2'`.
- Slice obligation order: `implementer`, `review`, `cleaner`, `architect`, `hardener`, `qa`, `final-suite`, `verified`. No `security` obligation exists at slice scope.
- Feature obligations: `feature-branch-review`, `feature-security-review`, `feature-findings-digest`, `feature-complete`.
- Finding origins: `Task Reviewer`, `Re-reviewer`, `Cleaner`, `Architect`, `Hardener`, `QA`, `Branch Reviewer`, `Security Reviewer`. Feature scope allows only `Branch Reviewer` and `Security Reviewer`. Slice scope allows every other origin.
- `Replay through` accepts only `re-review` or `downstream`.
- `Executor: fixer-max` on every repair-start. `Executor: fixer` fails. `Executor: hardener` is allowed only for a `Hardener` origin finding with `Replay through: downstream` (engine decision E6).
- Slice repair rounds cap at 5 per slice. Feature closing allows one repair round.
- `Replay status` on repair-finish is `VERIFIED` or `FAILED` (engine decision E10).
- Implementer report `Status:` is `DONE` or `DONE_WITH_CONCERNS` to leave `implementing`.
- Hardener FAIL accepts `Status: NOT VERIFIED` or `Status: REVERIFY_REQUIRED`.
- Consultation record fields, each exactly once, non-empty, single line: `Finding IDs`, `Case`, `Problem`, `Verdict`, `Recommendation`, `Basis`, `Risks and assumptions`, `Flip condition`, `Forward consult gates`, `Decision`, `Reason`, `Cost if wrong`, `Controller action`. `Case` is `C1` to `C5`. `Decision` is `FIX_NOW`, `NO_FIX`, `PARK`, `ESCALATE`, or `USER:<ruling>`. Fields the advisor did not state carry `NOT GIVEN`.
- Claude Code advisor is the built-in `advisor` tool. Codex advisor is the `$fable-advisor:advise` skill. Codex failure text: `Fable Advisor failed: <exact failure>. No advisory ruling was produced.`
- Security Reviewer runs once per feature on the whole branch. Claude model `fable`, effort `high`. Codex `gpt-5.6-sol`, `model_reasoning_effort = "xhigh"`.
- Commit messages carry no agent attribution. The claude-config repo (`~/.claude`, branch `main`) has about 145 unrelated dirty files. Every commit there uses `git add <named files>` only. Never `git add -A` or `git add .` there.
- Never commit `docs/superpowers/wayfinding/` or `package-lock.json` in the superpowers worktree.

## Working directories

- Superpowers worktree: `/Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership`, branch `worktree-gdd-security-ownership`. Tasks 1 to 6.
- Claude config repo: `/Users/bmurgic/.claude`, branch `main`. Tasks 7 and 8.

Every command below is written with an absolute path or an explicit `cd`. The shell does not keep its working directory between commands.

## Test status between tasks

The three script tests are one suite in practice: `gdd-finding-state.test.sh` and `gdd-slice-state.test.sh` drive `gdd-workflow-state`. Expected state after each task:

| After task | workflow-state.test | finding-state.test | slice-state.test | readiness test | parity test |
|---|---|---|---|---|---|
| 1 | green | red (uses `slice-1-security`) | red | green | green |
| 2 | green | red | red | green | green |
| 3 | green | green | red | green | green |
| 4 | green | green | green | green | green |
| 5 | green | green | green | green | green |
| 6 | green | green | green | green | green |
| 7 | green | green | green | green | green |
| 8 | green | green | green | green | green |

Do not skip or delete a red test to get past it. The task that owns the file turns it green.

## Engine decisions the spec leaves open

The reducer prints finding rows before static rows, and `claim_action` accepts only the first READY row. Every rule below was checked against that order.

- **E1 Review hold.** A review obligation owns findings: `slice-N-review` owns slice N findings with origin `Task Reviewer` or `Re-reviewer`, `feature-branch-review` owns `Branch Reviewer` findings, `feature-security-review` owns `Security Reviewer` findings. The static reducer forces a review to `PENDING` (held) while any owned finding is `REPORTED`, or `REPAIRING` with `Replay through: re-review` and either no repair-result accepted for its current round, or a repair-result accepted but the review already has an ACCEPT newer than that repair-result, or a repair-finish recorded. A review with no held reason follows the default rule (READY when not COMPLETE). `completed[]` bookkeeping is untouched, so prerequisites still resolve.
- **E2 Round flow.** `dispose` to REPAIRING, then `repair-start-R` per finding, then `repair-result` per finding with the fixer report, then the owning review is claimed and the re-reviewer report is accepted through `gdd-finding-state report`, then `repair-finish-R` per finding with the re-review report as `Replay evidence`, then `resolve` for VERIFIED finishes or `repair-start-(R+1)` for FAILED ones.
- **E3 Review result kind.** `gdd-finding-state report` computes the result for review origins. `Task Reviewer` and `Re-reviewer`: FAIL when any owned finding of the review is still `REPORTED` or `REPAIRING` before this report, or any new finding file carries `Severity claim: Critical` or `Severity claim: Important`. `Branch Reviewer` and `Security Reviewer`: FAIL when any owned finding is open or the new finding count is above zero. Otherwise PASS. The closing accept after all findings resolve is a `report` call with `Finding count: 0` and an empty directory, which yields PASS.
- **E4 Round numbering.** `next_round(scope)` is the highest `Repair round` recorded by any repair-start in the scope when some finding started that round without a finish, otherwise that maximum plus one (1 when none). The reducer names the row `repair-start-<next_round>` and `validate_repair_start` requires `Repair round` equal to `next_round`. The sequential-per-finding check is removed. The finding's own previous round must be lower.
- **E5 One fixer dispatch per round.** `repair-result` for a finding is READY only when no other REPAIRING finding in the same scope is still eligible to start the current round. Eligible means REPAIRING with no round started, or with its latest finish FAILED and the scope below its cap. Dispose rows print before repair rows so new re-review breakage is disposed before the next round starts.
- **E6 Hardener self-fix executor.** D4 lets the Hardener fix a mutation-suite defect itself. That finding carries `Executor: hardener` on its repair-start and the Hardener report as the repair-result evidence. Every other repair-start requires `Executor: fixer-max`.
- **E7 Downstream finish.** A `downstream` finding's `repair-finish-R` is READY when its round-R repair-result is accepted and a non-FAIL ACCEPT exists, newer than that repair-result, for a worker obligation of the slice at or after the origin's position (Cleaner=cleaner, Architect=architect, Hardener=hardener, QA=qa). `guard` allows only the target state produced by accepting the first worker obligation at or after the origin that is not COMPLETE in `projections/status.tsv`.
- **E8 Feature repair-start gate.** A feature-scope `repair-start` is READY only when both `feature-branch-review` and `feature-security-review` have at least one ACCEPT, so the Security Reviewer runs before the combined fix dispatch (D8).
- **E9 Invalidation.** Accepting `repair-result` for a `re-review` finding stages `EvidenceInvalidated` for the owning review (`slice-N-review`, or both feature reviews for feature scope). `downstream` findings invalidate nothing. Disposition to REPAIRING invalidates nothing.
- **E10 Finish status vocabulary.** D5 and D13 say `PASSED`. The engine keeps `Replay status: VERIFIED` because `RESOLVED` validation, the existing tests, and every fixture already use it.
- **E11 Consultation rows.** The reducer prints `finding-<id>-consult-<k>` COMPLETE for each recorded consultation and `finding-<id>-consult-<K+1>` PENDING while the finding is REPORTED or REPAIRING. `claim_action` accepts a PENDING consult row like it accepts a PENDING wake row. `consult` records `FindingConsultRecorded` with `finding-event-name consult-<k>`.
- **E12 DEFERRED needs no Fable result.** C5 lists DISMISSED, PARKED, and BLOCKED. `transition` to DEFERRED requires `Ruling`, `Cost if wrong`, and `Wake condition` only.
- **E13 Receipt header.** The claim receipt line becomes `workflow-format: 2`.
- **E14 Cap re-dispose.** When a finish is FAILED and the scope is at its cap (slice round 5 recorded, or any feature round), the reducer prints `dispose` READY again so the controller can consult (C3 or C4) and move the finding to DISMISSED, PARKED, or BLOCKED. The `REPAIRING -> DISMISSED|PARKED|BLOCKED` transitions already exist.

## File structure

Superpowers worktree:

- `skills/gauntlet-driven-development/scripts/gdd-workflow-state` (2278 lines): obligations, format version, origins, reducer, acceptance groups, projection.
- `skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh` (1573 lines).
- `skills/gauntlet-driven-development/scripts/gdd-finding-state` (800 lines): report, transition, repair-start, repair-finish, new `repair-result`, new `consult`, guard, digest.
- `skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh` (700 lines).
- `skills/gauntlet-driven-development/scripts/gdd-slice-state` (290 lines): slice projection adapter.
- `skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh` (203 lines).
- `skills/gauntlet-driven-development/scripts/gdd-readiness`: policy and format checks.
- `tests/openspec-gdd/test-gdd-readiness.sh`.
- `skills/gauntlet-driven-development/finding-policy.md` (99 lines).
- `skills/gauntlet-driven-development/SKILL.md` (382 lines).

Claude config repo:

- `agents/security-reviewer.md`, `agents/branch-reviewer.md`, `agents/architect.md`, `agents/e2e-runner.md`.
- `codex-agents/security-reviewer.toml`, `codex-agents/branch-reviewer.toml`, `codex-agents/architect.toml`, `codex-agents/e2e-runner.toml`.
- `hooks/guard-dispatch-model.sh`.
- `superpowers-bridge/scripts/agent-source-parity.test.sh`.

---

### Task 1: Static obligations, format version 2, review origins, projection

Working directory: `/Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership`.

**Files:**
- Modify: `skills/gauntlet-driven-development/scripts/gdd-workflow-state:124-166` (`compile_obligations`), `:206` (obligation ID regex), `:359-365` (`validate_format_version`), `:772` (`initialize_workflow` format write), `:1372` (receipt header), `:1496-1505` (`finding_origin_for_obligation`), `:1519-1571` (`validate_role_findings`), `:1444-1494` and `:1573-1638` (finding-origin metadata), `:1640-1700` (`accept_active_action`), `:1818-1824` (projection map), `:1887-1891` (latest-slice-states awk), `:2223-2230` (`format-version` command).
- Test: `skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh:287-291`, `:358`, `:373-374`, `:500-506`, `:1214-1215`, plus new tests appended before the final summary.

**Interfaces:**
- Produces obligation IDs `slice-N-review` (type `review`, evidence contract `review-report`, prerequisite `slice-N-implementer`) and `feature-security-review` (type `security-review`, evidence contract `security-review-report`, prerequisite every `slice-N-verified`). `feature-findings-digest` prerequisite is `feature-branch-review,feature-security-review`.
- Produces `finding_origin_for_obligation`: `slice-*-review` prints `Task Reviewer`, `feature-security-review` prints `Security Reviewer`. No `slice-*-security` case.
- Produces `finding_file_origin FILE` (prints the file's `Origin role`) and `finding_origin_is_authorized OBLIGATION ORIGIN` (exit 0 when allowed). Task 3 relies on the FindingReported metadata `finding-origin` being the file's own origin.
- Produces `require_evidence_status_one_of FILE LABEL STATUS...`.
- Slice projection states: `REVIEWING` after `slice-N-implementer` ACCEPT PASS, `VERIFYING: CLEANER` after `slice-N-review` ACCEPT PASS, `VERIFYING: HARDENER` after `slice-N-architect` ACCEPT PASS.

- [ ] **Step 1: Update the existing assertions that pin the old shape**

Edit `gdd-workflow-state.test.sh`:

Line 358, replace:

```bash
assert_file_contains "$WORKSPACE/workflow-v1/format-version" '1'
```

with:

```bash
assert_file_contains "$WORKSPACE/workflow-v1/format-version" '2'
```

After line 374 (the `feature-branch-review` obligations assertion), add:

```bash
assert_file_contains "$WORKSPACE/workflow-v1/obligations.tsv" $'slice-1-review\tslice-1\treview\tslice-1-implementer\tPASS,FAIL\tslice\treview-report'
assert_file_contains "$WORKSPACE/workflow-v1/obligations.tsv" $'slice-1-cleaner\tslice-1\tcleaner\tslice-1-review'
assert_file_contains "$WORKSPACE/workflow-v1/obligations.tsv" $'slice-1-hardener\tslice-1\thardener\tslice-1-architect'
assert_file_contains "$WORKSPACE/workflow-v1/obligations.tsv" $'feature-security-review\tfeature\tsecurity-review\tslice-1-verified,slice-2-verified\tPASS,FAIL\tfeature\tsecurity-review-report'
assert_file_contains "$WORKSPACE/workflow-v1/obligations.tsv" $'feature-findings-digest\tfeature\tfindings-digest\tfeature-branch-review,feature-security-review'
run_workflow "$PLAN_FILE" format-version
assert_status 0
assert_output_contains '2'
if grep -q 'slice-1-security' "$WORKSPACE/workflow-v1/obligations.tsv"; then
  record_fail 'no per-slice security obligation is compiled'
else
  record_pass 'no per-slice security obligation is compiled'
fi
```

Lines 500 and 506 (the `unknown-version` fixture), replace `2` with `1` in both:

```bash
printf '%s\n' 1 >"$JOURNAL/format-version"
```

```bash
assert_output_contains 'workflow format version is unknown: 1'
```

Lines 287-291 (`setup_claimed_hardener`), replace the loop header and its case:

```bash
  for role_obligation in slice-1-review slice-1-cleaner slice-1-architect; do
    case "$role_obligation" in
      slice-1-review) role_actor=task-reviewer ;;
      slice-1-cleaner) role_actor=cleaner ;;
      slice-1-architect) role_actor=architect ;;
    esac
```

Line 1215, replace:

```bash
assert_file_contains "$REPO/completion.md" 'Findings digest: events/controller-18.md'
```

with:

```bash
assert_file_contains "$REPO/completion.md" 'Branch review evidence: events/controller-17.md'
assert_file_contains "$REPO/completion.md" 'Findings digest: events/controller-19.md'
```

(The line-17 assertion at 1214 stays. Two slices at eight rows each occupy rows 1 to 16, `feature-branch-review` is 17, `feature-security-review` is 18, the digest is 19.)

- [ ] **Step 2: Add the new failing tests**

Append before the final `printf '\npass=%s fail=%s\n'` line of `gdd-workflow-state.test.sh`:

```bash
# Hardener REVERIFY_REQUIRED is a FAIL the engine accepts (spec D4).
setup_claimed_hardener 'hardener-reverify-required'
hardener_result="$REPO/hardener-reverify.md"
write_role_result "$hardener_result" REVERIFY_REQUIRED
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-hardener FAIL "$hardener_result"
assert_status 0
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Ready obligation: slice-1-hardener'

# A review obligation authorizes Task Reviewer and Re-reviewer findings and
# records each file's own origin. Any other origin is rejected.
initialize_journal_fixture 'review-origins'
JOURNAL="$WORKSPACE/workflow-v1"
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: review the slice.' >"$DISPATCH_FILE"
IMPLEMENTER_RESULT="$REPO/implementer.md"
printf 'Status: DONE\n' >"$IMPLEMENTER_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
implementer_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$implementer_receipt" PASS "$IMPLEMENTER_RESULT"
assert_status 0
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Ready obligation: slice-1-review'
assert_file_contains "$CHANGE/tasks.md" '**Slice state:** [~] REVIEWING'
REVIEW_FINDINGS="$REPO/review-findings"
mkdir -p "$REVIEW_FINDINGS"
REVIEW_RESULT="$REPO/review-result.md"
printf 'Status: FAIL\nFinding count: 1\n' >"$REVIEW_RESULT"
cat >"$REVIEW_FINDINGS/1.md" <<'EOF'
Origin role: Cleaner
Severity claim: Important
Blocking claim: yes
Observed failure: a worker origin on a review obligation.
Evidence: test evidence
Violated authority: task brief
Assumptions: none
Failure scenario: the wrong role owns the finding
Proposed repair: reject the origin
Repair effects: none
EOF
run_workflow "$PLAN_FILE" claim slice-1-review task-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$REVIEW_FINDINGS" "$PLAN_FILE" accept-active slice-1-review FAIL "$REVIEW_RESULT"
assert_status 1
assert_output_contains 'finding origin differs from claimed role: Task Reviewer or Re-reviewer'
sed -i.bak 's/^Origin role: Cleaner$/Origin role: Re-reviewer/' "$REVIEW_FINDINGS/1.md"
rm -f "$REVIEW_FINDINGS/1.md.bak"
run_grouped_workflow "$REVIEW_FINDINGS" "$PLAN_FILE" accept-active slice-1-review FAIL "$REVIEW_RESULT"
assert_status 0
review_metadata=$(grep -l $'^finding-origin\tRe-reviewer$' "$JOURNAL"/events/*/metadata.tsv | head -n 1)
if [ -n "$review_metadata" ]; then
  record_pass 'review finding metadata records the file origin Re-reviewer'
else
  record_fail 'review finding metadata records the file origin Re-reviewer'
fi
run_workflow "$PLAN_FILE" status
assert_status 0
assert_file_contains "$CHANGE/tasks.md" '**Slice state:** [~] REVIEWING'
```

- [ ] **Step 3: Run the test to verify it fails**

Run:

```bash
bash /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh 2>&1 | grep -E '^FAIL|^pass='
```

Expected: FAIL lines for the format-version `2` assertion, the `slice-1-review` obligation rows, `unknown: 1`, `setup_claimed_hardener` claims of `slice-1-review`, `controller-19`, REVERIFY_REQUIRED, and the review-origins block.

- [ ] **Step 4: Compile the new obligations**

In `gdd-workflow-state` `compile_obligations`, replace the block from `local implementer=` through the `$verified` row with:

```bash
    local implementer="slice-$slice_number-implementer"
    local review="slice-$slice_number-review"
    local cleaner="slice-$slice_number-cleaner"
    local architect="slice-$slice_number-architect"
    local hardener="slice-$slice_number-hardener"
    local qa="slice-$slice_number-qa"
    local final_suite="slice-$slice_number-final-suite"
    local verified="slice-$slice_number-verified"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$implementer" "$scope" implementer "$prior_verified" 'PASS,FAIL' slice 'implementer-report' >>"$output_file"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$review" "$scope" review "$implementer" 'PASS,FAIL' slice 'review-report' >>"$output_file"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$cleaner" "$scope" cleaner "$review" 'PASS,FAIL' slice 'cleaner-report' >>"$output_file"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$architect" "$scope" architect "$cleaner" 'PASS,FAIL' slice 'architect-report' >>"$output_file"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$hardener" "$scope" hardener "$architect" 'PASS,FAIL' slice 'hardener-report' >>"$output_file"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$qa" "$scope" qa "$hardener" 'PASS,FAIL' slice 'qa-report' >>"$output_file"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$final_suite" "$scope" final-suite "$qa" 'PASS,FAIL' slice 'final-suite-report' >>"$output_file"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$verified" "$scope" verified "$final_suite" PASS slice 'verification-record' >>"$output_file"
```

Replace the three feature rows after the loop with:

```bash
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' feature-branch-review feature branch-review "$verified_obligations" 'PASS,FAIL' feature 'branch-review-report' >>"$output_file"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' feature-security-review feature security-review "$verified_obligations" 'PASS,FAIL' feature 'security-review-report' >>"$output_file"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' feature-findings-digest feature findings-digest 'feature-branch-review,feature-security-review' PASS feature 'findings-digest' >>"$output_file"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' feature-complete feature complete feature-findings-digest PASS feature 'completion-evidence' >>"$output_file"
```

Line 206, replace the regex with:

```awk
      if ($1 !~ /^(slice-[1-9][0-9]*-(implementer|review|cleaner|architect|hardener|qa|final-suite|verified)|feature-(branch-review|security-review|findings-digest|complete))$/) {
```

- [ ] **Step 5: Move the format version to 2**

Replace `validate_format_version`:

```bash
validate_format_version() {
  local format_version
  format_version=$(cat "$workflow/format-version" 2>/dev/null) || invalid 'workflow format version is missing'
  [ "$format_version" = 2 ] || { printf '%s\n' "workflow format version is unknown: $format_version" >&2; return 1; }
}
```

Keep the existing first two lines of the function if they differ from the above. Only the literal `1` becomes `2`.

Line 772: `printf '%s\n' 2 >"$stage/format-version"`.

Line 1372: `printf '%s\n' 'workflow-format: 2'`.

In the `format-version)` command case (line 2223 onward), change the literal `1` that is printed when the workflow directory exists or does not exist to `2`. Search with:

```bash
sed -n '2223,2240p' /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts/gdd-workflow-state
```

- [ ] **Step 6: Authorize review origins and record each file's origin**

Replace `finding_origin_for_obligation`:

```bash
finding_origin_for_obligation() {
  case "$1" in
    slice-*-review) printf '%s\n' 'Task Reviewer' ;;
    slice-*-cleaner) printf '%s\n' Cleaner ;;
    slice-*-architect) printf '%s\n' Architect ;;
    slice-*-hardener) printf '%s\n' Hardener ;;
    slice-*-qa) printf '%s\n' QA ;;
    feature-branch-review) printf '%s\n' 'Branch Reviewer' ;;
    feature-security-review) printf '%s\n' 'Security Reviewer' ;;
    *) return 1 ;;
  esac
}

finding_file_origin() {
  awk -F ': ' '/^Origin role:/ { print $2; exit }' "$1"
}

finding_origin_is_authorized() {
  local obligation_id=$1
  local origin=$2
  case "$obligation_id" in
    slice-*-review)
      case "$origin" in 'Task Reviewer'|Re-reviewer) return 0 ;; esac
      return 1
      ;;
  esac
  [ "$origin" = "$(finding_origin_for_obligation "$obligation_id")" ]
}
```

In `validate_role_findings`, after the `authorized_origin=$(finding_origin_for_obligation ...)` assignment add:

```bash
  case "$obligation_id" in slice-*-review) authorized_origin='Task Reviewer or Re-reviewer' ;; esac
```

and replace the per-file origin check:

```bash
      finding_origin_is_authorized "$obligation_id" "$(finding_file_origin "$finding_file")" \
        || fail "finding origin differs from claimed role: $authorized_origin"
```

In `append_verified_group` and `append_role_result_group`, replace:

```bash
        printf 'finding-origin\t%s\n' "$finding_origin"
```

with:

```bash
        printf 'finding-origin\t%s\n' "$(finding_file_origin "$finding_file")"
```

- [ ] **Step 7: Accept Hardener REVERIFY_REQUIRED and feature security scope**

Add after `require_evidence_status`:

```bash
require_evidence_status_one_of() {
  local evidence_file=$1
  local evidence_label=$2
  shift 2
  local candidate
  [ -s "$evidence_file" ] || fail "$evidence_label evidence is missing or empty: $evidence_file"
  for candidate in "$@"; do
    if grep -Eq "^Status:[[:space:]]*${candidate}([[:space:]]|$)" "$evidence_file"; then
      return 0
    fi
  done
  fail "$evidence_label evidence must contain one of Status: $(printf '%s | ' "$@" | sed 's/ | $//'): $evidence_file"
}
```

In `accept_active_action`, replace the Hardener FAIL line:

```bash
          FAIL) require_evidence_status_one_of "$evidence_file" Hardener 'NOT VERIFIED' REVERIFY_REQUIRED ;;
```

Replace the `grouped_scope` case:

```bash
    case "$obligation_id" in
      slice-*-*)
        grouped_scope=${obligation_id#slice-}
        grouped_scope=${grouped_scope%%-*}
        ;;
      feature-branch-review|feature-security-review) grouped_scope=feature ;;
    esac
```

In the non-grouped `FindingReported` path, replace:

```bash
      feature-branch-review)
        [ "$GDD_FINDING_SCOPE" = feature ] || fail 'Branch Reviewer finding must use feature scope'
        ;;
```

with:

```bash
      feature-branch-review|feature-security-review)
        [ "$GDD_FINDING_SCOPE" = feature ] || fail "$authorized_origin finding must use feature scope"
        ;;
```

- [ ] **Step 8: Project REVIEWING**

In `build_projection_stage`, replace the ACCEPT map:

```bash
      ACCEPT:slice-*-implementer) projected_state=REVIEWING ;;
      ACCEPT:slice-*-review) projected_state='VERIFYING: CLEANER' ;;
      ACCEPT:slice-*-cleaner) projected_state='VERIFYING: ARCHITECT' ;;
      ACCEPT:slice-*-architect) projected_state='VERIFYING: HARDENER' ;;
      ACCEPT:slice-*-hardener) projected_state='VERIFYING: QA' ;;
      ACCEPT:slice-*-verified) projected_state=VERIFIED ;;
      *) projected_state='' ;;
```

In the latest-slice-states awk, replace the role map:

```awk
      if (role == "implementer") state[slice] = ($2 == "CLAIMED" ? "IMPLEMENTING" : "QUEUED")
      else if (role == "review") state[slice] = "REVIEWING"
      else if (role == "cleaner") state[slice] = "VERIFYING: CLEANER"
      else if (role == "architect") state[slice] = "VERIFYING: ARCHITECT"
      else if (role == "hardener") state[slice] = "VERIFYING: HARDENER"
      else state[slice] = "VERIFYING: QA"
```

In the tasks.md rewrite (search for `'VERIFYING: SECURITY'` in `build_projection_stage` and the `set_projected_slice_state` history handling), remove every `VERIFYING: SECURITY` case and add `REVIEWING` wherever the states are enumerated. Run:

```bash
grep -n 'SECURITY' /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts/gdd-workflow-state
```

Expected after the edit: no output.

- [ ] **Step 9: Run the test to verify it passes**

Run:

```bash
bash /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh 2>&1 | grep -E '^FAIL|^pass='
```

Expected: `pass=<n> fail=0`. The `repair-order` test at lines 866-925 still passes because `replay-entry`, `Executor: fixer`, and `Replay through: Cleaner` are removed in Task 2 and Task 3, not here.

- [ ] **Step 10: Commit**

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership && git add skills/gauntlet-driven-development/scripts/gdd-workflow-state skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh && git commit -m 'feat(gdd): compile review and feature security obligations at format 2'
```

### Task 2: Finding reducer for fix rounds, review holds, consultations, and invalidation

Working directory: `/Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership`.

**Files:**
- Modify: `skills/gauntlet-driven-development/scripts/gdd-workflow-state:367-453` (`reduce_workflow`), `:455-518` (`final_wave_is_pending`, `finding_event_facts`, `blocked_finding_boundaries`), `:520-683` (`reduce_finding_obligations`), `:851-879` (`obligation_allowed_result`), `:915-947` (`append_result_metadata`), `:965-992` (`replay_obligations_for_repair`, `replay_roles_through`), `:1226-1337` (`final_wave_registration_completes`, `append_repair_acceptance_group`), `:1339-1360` (`claim_action` exceptions), `:1573-1638` (`append_role_result_group` fixer case), `:1836-1856` and `:1896` (projection).
- Test: `skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh:866-925` (repair-order test), `:1177` (raw claim name), plus new tests appended before the final summary.

**Interfaces:**
- Consumes `finding_file_origin`, `finding_origin_is_authorized`, and the obligation IDs from Task 1.
- Produces `finding_event_facts` with 12 tab columns: sequence, result-kind, finding-id, finding-state, finding-scope, finding-origin, report-complete, repair-round, replay-status, replay-through, blocking-boundary, finding-event-name.
- Produces `accept_event_facts` with 3 tab columns: sequence, obligation-id, result-kind (`PASS` when no metadata exists).
- Produces `held_review_obligations` (one obligation ID per line) and `review_obligations_for_scope SCOPE`.
- Produces finding rows: `finding-<id>-supplement`, `-verify`, `-dispose`, `-consult-<k>`, `-repair-start-<r>`, `-repair-result`, `-repair-finish-<r>`, `-resolve`, `-digest`, `-wake`.
- Produces accepted result kinds for finding rows: `dispose`/`wake` → `FindingDispositionRecorded`, `consult-<k>` → `FindingConsultRecorded`, `repair-start-<r>` → `RepairStarted`, `repair-result` → `RepairAccepted` (metadata `repair-round`, `replay-through`), `repair-finish-<r>` → `RepairFinished` (metadata `repair-round`, `replay-status`), `resolve` → `FindingResolved`.
- Task 3 relies on every GDD_* environment variable that `append_result_metadata` still reads: `GDD_FINDING_ID`, `GDD_FINDING_SCOPE`, `GDD_FINDING_ORIGIN`, `GDD_REPORT_COMPLETE`, `GDD_FINDING_STATE`, `GDD_FINDING_EVENT_NAME`, `GDD_REPAIR_ROUND`, `GDD_REPLAY_STATUS`, `GDD_REPLAY_THROUGH`, `GDD_BLOCKING_BOUNDARY`, `GDD_FINDING_RULING`, `GDD_COST_IF_WRONG`, `GDD_WAKE_CONDITION`.

- [ ] **Step 1: Replace the repair-order test and the raw claim name**

In `gdd-workflow-state.test.sh`, delete lines 866-925 (from `DISPATCH_FILE="$REPO/dispatch.md"` after `initialize_journal_fixture 'repair-order'` through `assert_equals "$before_repair_finish_claim" ...`) together with the `initialize_journal_fixture 'repair-order'` line that precedes them. The new walk below replaces that regression.

Line 1177, replace `finding-GDD-F0005-replay-entry` with `finding-GDD-F0005-dispose` in the `append_event` call, and lines 1183 and 1188 likewise (`Active claim: finding-GDD-F0005-dispose`, `Resume claim: finding-GDD-F0005-dispose`).

- [ ] **Step 2: Add the failing round-walk tests**

Append before the final `printf '\npass=%s fail=%s\n'` line:

```bash
write_review_finding() {
  local output=$1 origin=$2 summary=$3 severity=${4:-Important}
  cat >"$output" <<EOF
Origin role: $origin
Severity claim: $severity
Blocking claim: yes
Observed failure: $summary
Evidence: test evidence
Violated authority: task brief
Assumptions: none
Failure scenario: the defect ships
Proposed repair: fix it
Repair effects: the fixer changes one file
EOF
}

finding_accept() {
  local obligation=$1 result_kind=$2 evidence=$3
  shift 3
  output=$(env "$@" "$WORKFLOW" "$PLAN_FILE" accept-active "$obligation" "$result_kind" "$evidence" 2>&1)
  status=$?
}

ready_obligation() {
  "$WORKFLOW" "$PLAN_FILE" next 2>/dev/null | sed -n 's/^Ready obligation: //p' | head -n 1
}

assert_next() {
  local expected=$1 actual
  actual=$(ready_obligation)
  if [ "$actual" = "$expected" ]; then
    record_pass "next obligation is $expected"
  else
    record_fail "next obligation is $expected (got: $actual)"
  fi
}

# Spec D3: Task Reviewer FAIL, consult, dispose, one fixer dispatch per round,
# re-review before any finish, finish, resolve, second round, closing PASS.
initialize_journal_fixture 'review-fix-round'
JOURNAL="$WORKSPACE/workflow-v1"
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: walk one fix round.' >"$DISPATCH_FILE"
EVIDENCE="$REPO/evidence.md"
printf 'Status: DONE\n' >"$EVIDENCE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
round_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$round_receipt" PASS "$EVIDENCE"
assert_status 0
ROUND_FINDINGS="$REPO/round-findings"
mkdir -p "$ROUND_FINDINGS"
write_review_finding "$ROUND_FINDINGS/1.md" 'Task Reviewer' 'the first defect'
write_review_finding "$ROUND_FINDINGS/2.md" 'Task Reviewer' 'the second defect'
REVIEW_RESULT="$REPO/review-result.md"
printf 'Status: FAIL\nFinding count: 2\n' >"$REVIEW_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-review task-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$ROUND_FINDINGS" "$PLAN_FILE" accept-active slice-1-review FAIL "$REVIEW_RESULT"
assert_status 0
run_workflow "$PLAN_FILE" status
assert_status 0
assert_file_contains "$JOURNAL/projections/status.tsv" $'slice-1-review\tPENDING'
assert_file_contains "$JOURNAL/projections/status.tsv" $'finding-GDD-F0001-consult-1\tPENDING'
assert_next finding-GDD-F0001-dispose

# A consultation is claimable while PENDING, like a wake check.
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-consult-1 controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-consult-1 FindingConsultRecorded "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=CONSULT GDD_FINDING_EVENT_NAME=consult-1
assert_status 0
run_workflow "$PLAN_FILE" status
assert_file_contains "$JOURNAL/projections/status.tsv" $'finding-GDD-F0001-consult-1\tCOMPLETE'
assert_file_contains "$JOURNAL/projections/status.tsv" $'finding-GDD-F0001-consult-2\tPENDING'

for finding in GDD-F0001 GDD-F0002; do
  run_workflow "$PLAN_FILE" claim "finding-$finding-dispose" controller "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-dispose" FindingDispositionRecorded "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
    GDD_FINDING_STATE=REPAIRING GDD_FINDING_EVENT_NAME=transition-repairing GDD_REPLAY_THROUGH=re-review
  assert_status 0
done
assert_next finding-GDD-F0001-repair-start-1
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-start-1 fixer-max "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-repair-start-1 RepairStarted "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=REPAIR_START GDD_FINDING_EVENT_NAME=repair-start GDD_REPAIR_ROUND=1
assert_status 0
# The second finding must start the round before the first can report a fixer result.
assert_next finding-GDD-F0002-repair-start-1
run_workflow "$PLAN_FILE" status
assert_file_contains "$JOURNAL/projections/status.tsv" $'finding-GDD-F0001-repair-result\tPENDING'
run_workflow "$PLAN_FILE" claim finding-GDD-F0002-repair-start-1 fixer-max "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0002-repair-start-1 RepairStarted "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0002 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=REPAIR_START GDD_FINDING_EVENT_NAME=repair-start GDD_REPAIR_ROUND=1
assert_status 0
assert_next finding-GDD-F0001-repair-result
for finding in GDD-F0001 GDD-F0002; do
  run_workflow "$PLAN_FILE" claim "finding-$finding-repair-result" fixer-max "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-repair-result" RepairAccepted "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
    GDD_FINDING_STATE=REPAIR_RESULT GDD_FINDING_EVENT_NAME=repair-result GDD_REPAIR_ROUND=1 GDD_REPLAY_THROUGH=re-review
  assert_status 0
done
# No finish is claimable before the re-review. The review is the next action.
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-finish-1 controller "$DISPATCH_FILE"
assert_status 1
assert_output_contains 'not the selected ready action'
assert_next slice-1-review
RE_REVIEW_FINDINGS="$REPO/re-review-findings"
mkdir -p "$RE_REVIEW_FINDINGS"
write_review_finding "$RE_REVIEW_FINDINGS/1.md" Re-reviewer 'new breakage from the fix'
printf 'Status: FAIL\nFinding count: 1\n' >"$REVIEW_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-review re-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$RE_REVIEW_FINDINGS" "$PLAN_FILE" accept-active slice-1-review FAIL "$REVIEW_RESULT"
assert_status 0
assert_next finding-GDD-F0001-repair-finish-1
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-finish-1 controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-repair-finish-1 RepairFinished "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=REPAIR_FINISH GDD_FINDING_EVENT_NAME=repair-finish GDD_REPAIR_ROUND=1 GDD_REPLAY_STATUS=VERIFIED
assert_status 0
run_workflow "$PLAN_FILE" claim finding-GDD-F0002-repair-finish-1 controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0002-repair-finish-1 RepairFinished "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0002 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=REPAIR_FINISH GDD_FINDING_EVENT_NAME=repair-finish GDD_REPAIR_ROUND=1 GDD_REPLAY_STATUS=FAILED
assert_status 0
# New breakage is disposed before the next round starts.
assert_next finding-GDD-F0003-dispose
run_workflow "$PLAN_FILE" claim finding-GDD-F0003-dispose controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0003-dispose FindingDispositionRecorded "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0003 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN=Re-reviewer \
  GDD_FINDING_STATE=REPAIRING GDD_FINDING_EVENT_NAME=transition-repairing GDD_REPLAY_THROUGH=re-review
assert_status 0
assert_next finding-GDD-F0001-resolve
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-resolve controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-resolve FindingResolved "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=RESOLVED GDD_FINDING_EVENT_NAME=transition-resolved
assert_status 0
# Round two is numbered from the slice, not from the finding.
assert_next finding-GDD-F0002-repair-start-2
for finding in GDD-F0002 GDD-F0003; do
  origin='Task Reviewer'
  [ "$finding" = GDD-F0002 ] || origin=Re-reviewer
  run_workflow "$PLAN_FILE" claim "finding-$finding-repair-start-2" fixer-max "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-repair-start-2" RepairStarted "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN="$origin" \
    GDD_FINDING_STATE=REPAIR_START GDD_FINDING_EVENT_NAME=repair-start GDD_REPAIR_ROUND=2
  assert_status 0
done
for finding in GDD-F0002 GDD-F0003; do
  origin='Task Reviewer'
  [ "$finding" = GDD-F0002 ] || origin=Re-reviewer
  run_workflow "$PLAN_FILE" claim "finding-$finding-repair-result" fixer-max "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-repair-result" RepairAccepted "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN="$origin" \
    GDD_FINDING_STATE=REPAIR_RESULT GDD_FINDING_EVENT_NAME=repair-result GDD_REPAIR_ROUND=2 GDD_REPLAY_THROUGH=re-review
  assert_status 0
done
assert_next slice-1-review
printf 'Status: FAIL\nFinding count: 0\n' >"$REVIEW_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-review re-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-review FAIL "$REVIEW_RESULT"
assert_status 0
for finding in GDD-F0002 GDD-F0003; do
  origin='Task Reviewer'
  [ "$finding" = GDD-F0002 ] || origin=Re-reviewer
  run_workflow "$PLAN_FILE" claim "finding-$finding-repair-finish-2" controller "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-repair-finish-2" RepairFinished "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN="$origin" \
    GDD_FINDING_STATE=REPAIR_FINISH GDD_FINDING_EVENT_NAME=repair-finish GDD_REPAIR_ROUND=2 GDD_REPLAY_STATUS=VERIFIED
  assert_status 0
  run_workflow "$PLAN_FILE" claim "finding-$finding-resolve" controller "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-resolve" FindingResolved "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN="$origin" \
    GDD_FINDING_STATE=RESOLVED GDD_FINDING_EVENT_NAME=transition-resolved
  assert_status 0
done
# Every re-review repair-result invalidated the review: two findings times two rounds.
review_invalidations=$(awk -F '\t' '$5 == "EvidenceInvalidated" && $4 == "slice-1-review" { count++ } END { print count + 0 }' "$JOURNAL/events.tsv")
assert_equals 4 "$review_invalidations"
assert_next slice-1-review
printf 'Status: PASS\nFinding count: 0\n' >"$REVIEW_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-review re-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-review PASS "$REVIEW_RESULT"
assert_status 0
assert_next slice-1-cleaner
assert_file_contains "$CHANGE/tasks.md" '**Slice state:** [~] VERIFYING: CLEANER'

# Spec D8: feature closing with one combined round, the Security Reviewer
# before the fix, both reviews invalidated, and a capped feature finding re-disposed.
initialize_journal_fixture 'feature-closing-round'
JOURNAL="$WORKSPACE/workflow-v1"
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: close the feature.' >"$DISPATCH_FILE"
EVIDENCE="$REPO/evidence.md"
printf 'Status: PASS\n' >"$EVIDENCE"
sequence=0
previous_hash=-
while IFS=$'\t' read -r obligation_id _scope _type _prerequisites _results _boundary _contract; do
  [ "$obligation_id" = obligation_id ] && continue
  case "$obligation_id" in feature-*) continue ;; esac
  sequence=$((sequence + 1))
  evidence_path="events/closing-$sequence.md"
  write_event_evidence "$JOURNAL" "$evidence_path" "Status: PASS $obligation_id"
  evidence_digest=$(sha256_file "$JOURNAL/$evidence_path")
  append_event "$JOURNAL" "$sequence" "$sequence" "event-$sequence" "$obligation_id" ACCEPT controller "receipt-$sequence" "$evidence_path" "$evidence_digest" "$previous_hash"
  previous_hash=$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')
done <"$JOURNAL/obligations.tsv"
assert_next feature-branch-review
BRANCH_FINDINGS="$REPO/branch-findings"
mkdir -p "$BRANCH_FINDINGS"
write_review_finding "$BRANCH_FINDINGS/1.md" 'Branch Reviewer' 'a seam between slices' Minor
BRANCH_RESULT="$REPO/branch-result.md"
printf 'Status: FAIL\nFinding count: 1\n' >"$BRANCH_RESULT"
run_workflow "$PLAN_FILE" claim feature-branch-review branch-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$BRANCH_FINDINGS" "$PLAN_FILE" accept-active feature-branch-review FAIL "$BRANCH_RESULT"
assert_status 0
assert_next finding-GDD-F0001-dispose
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-dispose controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-dispose FindingDispositionRecorded "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Branch Reviewer' \
  GDD_FINDING_STATE=REPAIRING GDD_FINDING_EVENT_NAME=transition-repairing GDD_REPLAY_THROUGH=re-review
assert_status 0
# The Security Reviewer runs before the combined fix dispatch.
run_workflow "$PLAN_FILE" status
assert_file_contains "$JOURNAL/projections/status.tsv" $'finding-GDD-F0001-repair-start-1\tPENDING'
assert_file_contains "$JOURNAL/projections/status.tsv" $'feature-branch-review\tPENDING'
assert_next feature-security-review
SECURITY_FINDINGS="$REPO/security-findings"
mkdir -p "$SECURITY_FINDINGS"
write_review_finding "$SECURITY_FINDINGS/1.md" 'Security Reviewer' 'a cross-slice authorization gap' Critical
SECURITY_RESULT="$REPO/security-result.md"
printf 'Status: FAIL\nFinding count: 1\n' >"$SECURITY_RESULT"
run_workflow "$PLAN_FILE" claim feature-security-review security-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$SECURITY_FINDINGS" "$PLAN_FILE" accept-active feature-security-review FAIL "$SECURITY_RESULT"
assert_status 0
security_metadata=$(grep -l $'^finding-origin\tSecurity Reviewer$' "$JOURNAL"/events/*/metadata.tsv | head -n 1)
if [ -n "$security_metadata" ]; then
  record_pass 'feature security review records a Security Reviewer finding'
else
  record_fail 'feature security review records a Security Reviewer finding'
fi
assert_next finding-GDD-F0002-dispose
run_workflow "$PLAN_FILE" claim finding-GDD-F0002-dispose controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0002-dispose FindingDispositionRecorded "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0002 GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Security Reviewer' \
  GDD_FINDING_STATE=REPAIRING GDD_FINDING_EVENT_NAME=transition-repairing GDD_REPLAY_THROUGH=re-review
assert_status 0
assert_next finding-GDD-F0001-repair-start-1
for finding in GDD-F0001 GDD-F0002; do
  origin='Branch Reviewer'
  [ "$finding" = GDD-F0001 ] || origin='Security Reviewer'
  run_workflow "$PLAN_FILE" claim "finding-$finding-repair-start-1" fixer-max "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-repair-start-1" RepairStarted "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN="$origin" \
    GDD_FINDING_STATE=REPAIR_START GDD_FINDING_EVENT_NAME=repair-start GDD_REPAIR_ROUND=1
  assert_status 0
done
for finding in GDD-F0001 GDD-F0002; do
  origin='Branch Reviewer'
  [ "$finding" = GDD-F0001 ] || origin='Security Reviewer'
  run_workflow "$PLAN_FILE" claim "finding-$finding-repair-result" fixer-max "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-repair-result" RepairAccepted "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN="$origin" \
    GDD_FINDING_STATE=REPAIR_RESULT GDD_FINDING_EVENT_NAME=repair-result GDD_REPAIR_ROUND=1 GDD_REPLAY_THROUGH=re-review
  assert_status 0
done
feature_invalidations=$(awk -F '\t' '$5 == "EvidenceInvalidated" { print $4 }' "$JOURNAL/events.tsv" | sort | uniq -c | awk '{ print $2 "=" $1 }' | paste -sd, -)
assert_equals 'feature-branch-review=2,feature-security-review=2' "$feature_invalidations"
assert_next feature-branch-review
printf 'Status: FAIL\nFinding count: 0\n' >"$BRANCH_RESULT"
run_workflow "$PLAN_FILE" claim feature-branch-review branch-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active feature-branch-review FAIL "$BRANCH_RESULT"
assert_status 0
assert_next finding-GDD-F0001-repair-finish-1
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-finish-1 controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-repair-finish-1 RepairFinished "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Branch Reviewer' \
  GDD_FINDING_STATE=REPAIR_FINISH GDD_FINDING_EVENT_NAME=repair-finish GDD_REPAIR_ROUND=1 GDD_REPLAY_STATUS=FAILED
assert_status 0
# Feature closing allows one round: a FAILED finish reopens dispose (E14).
assert_next finding-GDD-F0001-dispose
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-dispose controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-dispose FindingDispositionRecorded "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Branch Reviewer' \
  GDD_FINDING_STATE=DISMISSED GDD_FINDING_EVENT_NAME=transition-dismissed
assert_status 0
assert_next feature-branch-review
printf 'Status: PASS\nFinding count: 0\n' >"$BRANCH_RESULT"
run_workflow "$PLAN_FILE" claim feature-branch-review branch-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active feature-branch-review PASS "$BRANCH_RESULT"
assert_status 0
assert_next feature-security-review
printf 'Status: FAIL\nFinding count: 0\n' >"$SECURITY_RESULT"
run_workflow "$PLAN_FILE" claim feature-security-review security-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active feature-security-review FAIL "$SECURITY_RESULT"
assert_status 0
assert_next finding-GDD-F0002-repair-finish-1
run_workflow "$PLAN_FILE" claim finding-GDD-F0002-repair-finish-1 controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0002-repair-finish-1 RepairFinished "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0002 GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Security Reviewer' \
  GDD_FINDING_STATE=REPAIR_FINISH GDD_FINDING_EVENT_NAME=repair-finish GDD_REPAIR_ROUND=1 GDD_REPLAY_STATUS=VERIFIED
assert_status 0
assert_next finding-GDD-F0002-resolve
run_workflow "$PLAN_FILE" claim finding-GDD-F0002-resolve controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0002-resolve FindingResolved "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0002 GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Security Reviewer' \
  GDD_FINDING_STATE=RESOLVED GDD_FINDING_EVENT_NAME=transition-resolved
assert_status 0
assert_next feature-security-review
printf 'Status: PASS\nFinding count: 0\n' >"$SECURITY_RESULT"
run_workflow "$PLAN_FILE" claim feature-security-review security-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active feature-security-review PASS "$SECURITY_RESULT"
assert_status 0
assert_next feature-findings-digest

# Spec D5 downstream: a worker observation resolves after the next worker accepts PASS.
initialize_journal_fixture 'downstream-repair'
JOURNAL="$WORKSPACE/workflow-v1"
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: downstream repair.' >"$DISPATCH_FILE"
EVIDENCE="$REPO/evidence.md"
printf 'Status: DONE\n' >"$EVIDENCE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
downstream_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$downstream_receipt" PASS "$EVIDENCE"
assert_status 0
ROLE_RESULT="$REPO/role-result.md"
printf 'Status: PASS\nFinding count: 0\n' >"$ROLE_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-review task-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-review PASS "$ROLE_RESULT"
assert_status 0
CLEANER_FINDINGS="$REPO/cleaner-findings"
mkdir -p "$CLEANER_FINDINGS"
write_review_finding "$CLEANER_FINDINGS/1.md" Cleaner 'a duplicated helper' Minor
printf 'Status: PASS\nFinding count: 1\n' >"$ROLE_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-cleaner cleaner "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$CLEANER_FINDINGS" "$PLAN_FILE" accept-active slice-1-cleaner PASS "$ROLE_RESULT"
assert_status 0
assert_next finding-GDD-F0001-dispose
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-dispose controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-dispose FindingDispositionRecorded "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN=Cleaner \
  GDD_FINDING_STATE=REPAIRING GDD_FINDING_EVENT_NAME=transition-repairing GDD_REPLAY_THROUGH=downstream
assert_status 0
assert_next finding-GDD-F0001-repair-start-1
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-start-1 fixer-max "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-repair-start-1 RepairStarted "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN=Cleaner \
  GDD_FINDING_STATE=REPAIR_START GDD_FINDING_EVENT_NAME=repair-start GDD_REPAIR_ROUND=1
assert_status 0
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-result fixer-max "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-repair-result RepairAccepted "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN=Cleaner \
  GDD_FINDING_STATE=REPAIR_RESULT GDD_FINDING_EVENT_NAME=repair-result GDD_REPAIR_ROUND=1 GDD_REPLAY_THROUGH=downstream
assert_status 0
# Downstream repairs invalidate nothing and wait for the next worker.
downstream_invalidations=$(awk -F '\t' '$5 == "EvidenceInvalidated" { count++ } END { print count + 0 }' "$JOURNAL/events.tsv")
assert_equals 0 "$downstream_invalidations"
assert_next slice-1-architect
printf 'Status: PASS\nFinding count: 0\n' >"$ROLE_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-architect architect "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-architect PASS "$ROLE_RESULT"
assert_status 0
assert_next finding-GDD-F0001-repair-finish-1
```

- [ ] **Step 3: Run the test to verify it fails**

Run:

```bash
bash /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh 2>&1 | grep -E '^FAIL|^pass='
```

Expected: FAIL lines starting at `slice-1-review PENDING`, the consult rows, and the round walk. The three fixtures above fail because the reducer still prints `replay-entry` rows and never holds a review.

- [ ] **Step 4: Replace the fact readers**

Delete `final_wave_is_pending` (lines 455-461). Replace `finding_event_facts` with:

```bash
finding_event_facts() {
  local sequence event_id metadata_file result_kind finding_id finding_state finding_scope finding_origin report_complete repair_round replay_status replay_through blocking_boundary finding_event_name
  while IFS=$'\t' read -r sequence _revision event_id _obligation_id _kind _actor _receipt _evidence_path _evidence_sha256 _previous_hash _event_hash; do
    [ "$sequence" = sequence ] && continue
    metadata_file="$workflow/events/$event_id/metadata.tsv"
    [ -f "$metadata_file" ] || continue
    result_kind=$(metadata_value "$metadata_file" result-kind)
    finding_id=$(metadata_value "$metadata_file" finding-id)
    [ -n "$finding_id" ] || continue
    finding_state=$(metadata_value "$metadata_file" finding-state)
    finding_scope=$(metadata_value "$metadata_file" finding-scope)
    finding_origin=$(metadata_value "$metadata_file" finding-origin)
    report_complete=$(metadata_value "$metadata_file" report-complete)
    repair_round=$(metadata_value "$metadata_file" repair-round)
    replay_status=$(metadata_value "$metadata_file" replay-status)
    replay_through=$(metadata_value "$metadata_file" replay-through)
    blocking_boundary=$(metadata_value "$metadata_file" blocking-boundary)
    finding_event_name=$(metadata_value "$metadata_file" finding-event-name)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$sequence" "$result_kind" "$finding_id" "$finding_state" "$finding_scope" "$finding_origin" "$report_complete" "$repair_round" "$replay_status" "$replay_through" "$blocking_boundary" "$finding_event_name"
  done <"$workflow/events.tsv"
}

accept_event_facts() {
  local sequence event_id obligation_id event_kind metadata_file result_kind
  while IFS=$'\t' read -r sequence _revision event_id obligation_id event_kind _actor _receipt _evidence_path _evidence_sha256 _previous_hash _event_hash; do
    [ "$sequence" = sequence ] && continue
    [ "$event_kind" = ACCEPT ] || continue
    metadata_file="$workflow/events/$event_id/metadata.tsv"
    result_kind=PASS
    [ ! -f "$metadata_file" ] || result_kind=$(metadata_value "$metadata_file" result-kind)
    printf '%s\t%s\t%s\n' "$sequence" "$obligation_id" "${result_kind:-PASS}"
  done <"$workflow/events.tsv"
}

accept_facts_list() {
  accept_event_facts | awk -F '\t' '{ printf "%s%s:%s:%s", (NR > 1 ? "," : ""), $1, $2, $3 }'
}
```

In `blocked_finding_boundaries`, change `boundary[$3] = $12` to `boundary[$3] = $11`.

- [ ] **Step 5: Add the shared tracking awk and the review hold**

Insert directly after `accept_facts_list`:

```bash
# Shared awk for the finding reducer and the review hold. Input rows are
# finding_event_facts (12 columns). The accept_facts variable carries
# "sequence:obligation:result" entries separated by commas.
readonly FINDING_TRACKING_AWK='
  function review_owner(id) {
    if (scope[id] == "feature") {
      if (origin[id] == "Branch Reviewer") return "feature-branch-review"
      if (origin[id] == "Security Reviewer") return "feature-security-review"
      return ""
    }
    if (origin[id] == "Task Reviewer" || origin[id] == "Re-reviewer") return "slice-" scope[id] "-review"
    return ""
  }
  function worker_position(role) {
    if (role == "cleaner" || role == "Cleaner") return 1
    if (role == "architect" || role == "Architect") return 2
    if (role == "hardener" || role == "Hardener") return 3
    if (role == "qa" || role == "QA") return 4
    return 0
  }
  function scope_cap(finding_scope) { return finding_scope == "feature" ? 1 : 5 }
  function scope_next_round(finding_scope, candidate, other) {
    candidate = scope_max[finding_scope] + 0
    if (candidate == 0) return 1
    for (other in state) {
      if (scope[other] == finding_scope && started[other, candidate] && !finished[other, candidate]) return candidate
    }
    return candidate + 1
  }
  function round_open(id) { return round[id] > 0 && !finished[id, round[id]] }
  function latest_finish_failed(id) { return round[id] > 0 && finished[id, round[id]] && finish_status[id, round[id]] == "FAILED" }
  function eligible_to_start(id) {
    if (state[id] != "REPAIRING") return 0
    if (round[id] == 0) return 1
    return latest_finish_failed(id)
  }
  function capped(id) { return eligible_to_start(id) && scope_next_round(scope[id]) > scope_cap(scope[id]) }
  function can_start(id) { return eligible_to_start(id) && !capped(id) }
  function feature_reviews_accepted() { return ("feature-branch-review" in accepted_any) && ("feature-security-review" in accepted_any) }
  function start_ready(id) {
    if (!can_start(id)) return 0
    if (scope[id] == "feature") return feature_reviews_accepted()
    return 1
  }
  function others_pending_start(id, other) {
    for (other in state) {
      if (other != id && scope[other] == scope[id] && can_start(other)) return 1
    }
    return 0
  }
  function downstream_verified(id, r, accept_index, obligation_parts) {
    for (accept_index = 1; accept_index <= accept_count; accept_index++) {
      if (accept_result[accept_index] == "FAIL") continue
      if (accept_sequence[accept_index] <= accepted_sequence[id, r]) continue
      if (accept_obligation[accept_index] !~ /^slice-[0-9]+-(cleaner|architect|hardener|qa)$/) continue
      split(accept_obligation[accept_index], obligation_parts, "-")
      if (obligation_parts[2] != scope[id]) continue
      if (worker_position(obligation_parts[3]) >= worker_position(origin[id])) return 1
    }
    return 0
  }
  function finish_ready(id, r) {
    if (!accepted[id, r]) return 0
    if (replay_through[id] == "downstream") return downstream_verified(id, r)
    return last_accept[review_owner(id)] > accepted_sequence[id, r]
  }
  BEGIN {
    accept_count = split(accept_facts, accept_list, ",")
    for (accept_index = 1; accept_index <= accept_count; accept_index++) {
      split(accept_list[accept_index], accept_parts, ":")
      accept_sequence[accept_index] = accept_parts[1] + 0
      accept_obligation[accept_index] = accept_parts[2]
      accept_result[accept_index] = accept_parts[3]
      accepted_any[accept_parts[2]] = 1
      if (accept_parts[1] + 0 > last_accept[accept_parts[2]]) last_accept[accept_parts[2]] = accept_parts[1] + 0
    }
  }
  {
    result = $2
    id = $3
    if (!(id in seen)) {
      seen[id] = ++count
      ordered[count] = id
    }
    if (result == "FindingReported") {
      state[id] = "REPORTED"
      complete[id] = ($7 == "yes")
      was_incomplete[id] = ($7 != "yes")
      scope[id] = $5
      origin[id] = $6
    } else if (result == "FindingSupplemented") {
      complete[id] = 1
      supplemented[id] = 1
    } else if (result == "FindingDispositionRecorded") {
      state[id] = $4
      if ($4 == "REPAIRING") replay_through[id] = $10
    } else if (result == "RepairStarted") {
      started[id, $8] = 1
      round[id] = $8 + 0
      if ($8 + 0 > scope_max[scope[id]]) scope_max[scope[id]] = $8 + 0
    } else if (result == "RepairAccepted") {
      accepted[id, $8] = 1
      accepted_sequence[id, $8] = $1 + 0
    } else if (result == "RepairFinished") {
      finished[id, $8] = 1
      finish_status[id, $8] = $9
    } else if (result == "FindingResolved") {
      state[id] = "RESOLVED"
    } else if (result == "FindingConsultRecorded") {
      consults[id]++
    } else if (result == "FindingsDigestWritten") {
      digest_written = 1
    }
  }
'

held_review_obligations() {
  finding_event_facts | awk -F '\t' -v accept_facts="$(accept_facts_list)" "$FINDING_TRACKING_AWK"'
    END {
      for (id in state) {
        owner = review_owner(id)
        if (owner == "") continue
        if (state[id] == "REPORTED") { held[owner] = 1; continue }
        if (state[id] != "REPAIRING" || replay_through[id] != "re-review") continue
        r = round[id]
        if (r == 0 || !accepted[id, r]) { held[owner] = 1; continue }
        if (finished[id, r]) { held[owner] = 1; continue }
        if (last_accept[owner] > accepted_sequence[id, r]) held[owner] = 1
      }
      for (owner in held) print owner
    }
  '
}
```

Note: `readonly FINDING_TRACKING_AWK=` must sit at file top level (not inside a function) so both callers see it. Put it directly after `accept_facts_list`.

- [ ] **Step 6: Hold reviews in the static reducer**

In `reduce_workflow`, replace:

```bash
  local blocked_boundaries failed_accept_events final_wave_pending static_reduction
  blocked_boundaries=$(blocked_finding_boundaries | paste -sd, -)
  failed_accept_events=$(failed_accept_event_ids | paste -sd, -)
  final_wave_pending=$(final_wave_is_pending)
  static_reduction=$(awk -F '\t' -v blocked_boundaries="$blocked_boundaries" -v failed_accept_events="$failed_accept_events" -v final_wave_pending="$final_wave_pending" '
```

with:

```bash
  local blocked_boundaries failed_accept_events held_reviews static_reduction
  blocked_boundaries=$(blocked_finding_boundaries | paste -sd, -)
  failed_accept_events=$(failed_accept_event_ids | paste -sd, -)
  held_reviews=$(held_review_obligations | paste -sd, -)
  static_reduction=$(awk -F '\t' -v blocked_boundaries="$blocked_boundaries" -v failed_accept_events="$failed_accept_events" -v held_reviews="$held_reviews" '
```

In the awk `BEGIN` block, after the `failed[...]` loop add:

```awk
      held_count = split(held_reviews, held_list, ",")
      for (held_index = 1; held_index <= held_count; held_index++) {
        if (held_list[held_index] != "") {
          held[held_list[held_index]] = 1
        }
      }
```

Replace the start of the END decision chain:

```awk
        if (blocked[identifier]) {
          state = "PENDING"
        } else if (active[identifier]) {
          state = "CLAIMED"
        } else if (held[identifier]) {
          state = "PENDING"
        } else if (completed[identifier]) {
          state = "COMPLETE"
        } else {
```

(The `feature-branch-review && final_wave_pending` branch is gone. `CLAIMED` moves ahead of `COMPLETE` and `held` so a claimed re-review is displayed as claimed.)

- [ ] **Step 7: Rewrite the finding reducer**

Replace the whole `reduce_finding_obligations` function with:

```bash
reduce_finding_obligations() {
  finding_event_facts | awk -F '\t' -v accept_facts="$(accept_facts_list)" "$FINDING_TRACKING_AWK"'
    END {
      for (position = 1; position <= count; position++) {
        id = ordered[position]
        if (was_incomplete[id]) {
          print "finding-" id "-supplement\t" (supplemented[id] ? "COMPLETE" : "READY")
        }
        print "finding-" id "-verify\t" (complete[id] ? "COMPLETE" : "PENDING")
        if (state[id] == "REPORTED") {
          print "finding-" id "-dispose\t" (complete[id] ? "READY" : "PENDING")
        } else if (state[id] == "REPAIRING" && capped(id)) {
          print "finding-" id "-dispose\tREADY"
        } else {
          print "finding-" id "-dispose\tCOMPLETE"
        }
        if (state[id] == "REPORTED" || state[id] == "REPAIRING") {
          for (consult = 1; consult <= consults[id]; consult++) {
            print "finding-" id "-consult-" consult "\tCOMPLETE"
          }
          print "finding-" id "-consult-" (consults[id] + 1) "\tPENDING"
        }
      }
      for (position = 1; position <= count; position++) {
        id = ordered[position]
        if (state[id] == "REPAIRING") {
          r = round[id]
          if (round_open(id)) {
            print "finding-" id "-repair-start-" r "\tCOMPLETE"
            if (!accepted[id, r]) {
              print "finding-" id "-repair-result\t" (others_pending_start(id) ? "PENDING" : "READY")
            } else {
              print "finding-" id "-repair-result\tCOMPLETE"
              print "finding-" id "-repair-finish-" r "\t" (finish_ready(id, r) ? "READY" : "PENDING")
            }
          } else if (r > 0 && finish_status[id, r] == "VERIFIED") {
            print "finding-" id "-repair-finish-" r "\tCOMPLETE"
            print "finding-" id "-resolve\tREADY"
          } else if (can_start(id)) {
            print "finding-" id "-repair-start-" scope_next_round(scope[id]) "\t" (start_ready(id) ? "READY" : "PENDING")
          }
        }
        if (state[id] == "DEFERRED" || state[id] == "DISMISSED" || state[id] == "PARKED") {
          print "finding-" id "-digest\t" (digest_written ? "COMPLETE" : "PENDING")
          print "finding-" id "-wake\t" (digest_written ? "READY" : "PENDING")
        } else if (state[id] == "BLOCKED") {
          print "finding-" id "-wake\tBLOCKED"
        }
      }
    }
  '
}
```

In `reduce_workflow`, change the call `reduce_finding_obligations "$static_reduction"` to `reduce_finding_obligations` (no argument).

- [ ] **Step 8: Update allowed results, metadata, claim exceptions, and invalidation**

In `obligation_allowed_result`, delete the `replay-entry:ReplayEntered` line and add after the `wake` line:

```bash
    finding-GDD-F[0-9][0-9][0-9][0-9]-consult-[1-9]:FindingConsultRecorded|\
```

In `append_result_metadata`, delete these lines:

```bash
    [ -z "${GDD_TARGET_SLICE:-}" ] || printf 'target-slice\t%s\n' "$GDD_TARGET_SLICE"
    [ -z "${GDD_AFFECTED_SLICES:-}" ] || printf 'affected-slices\t%s\n' "$GDD_AFFECTED_SLICES"
    [ -z "${GDD_REPLAY_FULL_LIFECYCLE:-}" ] || printf 'replay-full-lifecycle\t%s\n' "$GDD_REPLAY_FULL_LIFECYCLE"
    if [ -n "${GDD_FINAL_WAVE_FINDINGS:-}" ]; then
      printf 'final-wave-id\tGDD-W%s\n' "$(sha256_values "$GDD_FINAL_WAVE_FINDINGS")"
      printf 'final-wave-findings\t%s\n' "$GDD_FINAL_WAVE_FINDINGS"
    fi
```

Delete `replay_obligations_for_repair` and `replay_roles_through` (lines 965-992) and `final_wave_registration_completes` (lines 1226-1244).

In `claim_action`, add a second exception case before `*:BLOCKED)`:

```bash
    finding-GDD-F[0-9][0-9][0-9][0-9]-consult-[1-9]:PENDING)
      # The controller records an advisor consultation before it disposes or
      # re-disposes the finding. The consult row is never the selected action.
      ;;
```

Replace `append_repair_acceptance_group` with:

```bash
review_obligations_for_scope() {
  case "$1" in
    feature) printf '%s\n' feature-branch-review feature-security-review ;;
    *) printf 'slice-%s-review\n' "$1" ;;
  esac
}

append_repair_acceptance_group() {
  local obligation_id=$1
  local actor=$2
  local receipt=$3
  local evidence_file=$4
  local metadata_file=$5
  shift 5
  local stage="$workflow/.stage.$$"
  [ ! -e "$stage" ] || fail "workflow transaction stage already exists: $stage"
  mkdir -p "$stage/events"
  cp "$workflow/events.tsv" "$stage/events.tsv"
  local sequence accepted_event_id
  sequence=$(next_sequence)
  accepted_event_id=$(stage_event "$stage" "$sequence" "$obligation_id" ACCEPT "$actor" "$receipt" "$evidence_file" result "$metadata_file" "$@") || return 75

  local result_kind finding_scope replay_through invalidated_obligation invalidation_metadata
  result_kind=$(metadata_value "$metadata_file" result-kind)
  finding_scope=$(metadata_value "$metadata_file" finding-scope)
  replay_through=$(metadata_value "$metadata_file" replay-through)
  if [ "$result_kind" = RepairAccepted ] && [ "$replay_through" = re-review ]; then
    while IFS= read -r invalidated_obligation; do
      [ -n "$invalidated_obligation" ] || continue
      sequence=$((sequence + 1))
      invalidation_metadata=$(mktemp)
      {
        printf 'accepted-event-id\t%s\n' "$accepted_event_id"
        printf 'invalidated-obligation\t%s\n' "$invalidated_obligation"
      } >"$invalidation_metadata"
      stage_event "$stage" "$sequence" "$invalidated_obligation" EvidenceInvalidated "$actor" "$receipt" "$evidence_file" invalidation "$invalidation_metadata" >/dev/null || {
        rm -f "$invalidation_metadata"
        return 75
      }
      rm -f "$invalidation_metadata"
    done < <(review_obligations_for_scope "$finding_scope")
  fi

  write_staged_manifest "$stage"
  publish_staged_transaction "$stage" || return $?
  printf '%s\n' "$accepted_event_id"
}
```

In `append_role_result_group`, delete the whole `case "$actor" in fixer|fixer-max) ... esac` block.

- [ ] **Step 9: Remove repair projection**

In `build_projection_stage`, delete the `if [ "$result_kind" = ReplayEntered ]; then ... fi` block and the `if [ "$result_kind" = RepairAccepted ]; then ... fi` block (lines 1841-1855). In the latest-slice-states awk END block, delete:

```awk
        if (historical[slice] == "REPAIRING") state[slice] = "REPAIRING"
```

Then check that nothing references the removed machinery:

```bash
grep -n 'final_wave\|affected_slices\|affected-slices\|replay_full\|ReplayEntered\|replay-entry\|target-slice\|GDD_TARGET_SLICE\|role_rank\|replay_is_complete\|REPAIRING' /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts/gdd-workflow-state
```

Expected: only the finding-state references to `REPAIRING` inside `FINDING_TRACKING_AWK`, `held_review_obligations`, and `reduce_finding_obligations`. No `final_wave`, `affected`, `ReplayEntered`, `replay-entry`, or `target-slice` hits.

- [ ] **Step 10: Run the test to verify it passes**

Run:

```bash
bash /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh 2>&1 | grep -E '^FAIL|^pass='
```

Expected: `pass=<n> fail=0`.

- [ ] **Step 11: Commit**

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership && git add skills/gauntlet-driven-development/scripts/gdd-workflow-state skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh && git commit -m 'feat(gdd): reduce fix rounds, review holds, and consultations'
```

### Task 3: Finding-state commands for fix rounds, consultations, and origins

**Files:**
- Modify: `skills/gauntlet-driven-development/scripts/gdd-finding-state` (usage 10-24, `validate_scope_origin` 56-73, `validate_replay_origin` 200-202, delete `validate_affected_slices` 204-221 and `validate_final_wave_findings` 223-243, `validate_transition_evidence` 245-314, `validate_repair_start` 359-398, delete `rank_for_target` 426-436, `rank_for_origin` 438-440, `slice_is_verified` 446-450, `accept_finding_result` 467-492, `command_report` 499-550, `origin_obligation_id` 552-563, `command_transition` 577-627, `command_guard` 655-689, delete `command_repair_entry` 691-725, `command_digest` 727-778, dispatch 789-800)
- Test: `skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh`

**Interfaces:**
- Consumes from Task 1 and Task 2: obligation ids `slice-N-review`, `feature-security-review`; claim ids `finding-<ID>-dispose`, `finding-<ID>-consult-K`, `finding-<ID>-repair-start-R`, `finding-<ID>-repair-result-R`, `finding-<ID>-repair-finish-R`, `finding-<ID>-resolve`; result kinds `FindingReported`, `FindingDispositionRecorded`, `RepairAccepted`, `FindingConsultRecorded`; env `GDD_FINDING_STATE`, `GDD_FINDING_EVENT_NAME`, `GDD_REPAIR_ROUND`, `GDD_REPLAY_STATUS`, `GDD_REPLAY_THROUGH`, `GDD_BLOCKING_BOUNDARY`, `GDD_FINDINGS_DIR`.
- Produces commands (Task 4 and the skill call them):
  - `gdd-finding-state PLAN report SCOPE ORIGIN ROLE_REPORT FINDINGS_DIR [FINAL_SUITE_REPORT]`. Reviewer origins accept the review obligation with the result kind rule E3. Prints new finding ids.
  - `gdd-finding-state PLAN transition FINDING_ID STATE EVIDENCE_FILE`. `REPAIRING` evidence carries `Repair hypothesis`, `Repair base`, `Replay through: re-review|downstream`.
  - `gdd-finding-state PLAN consult FINDING_ID CONSULT_FILE`. Requires the active claim `finding-<ID>-consult-K`.
  - `gdd-finding-state PLAN repair-start FINDING_ID EVIDENCE_FILE`. Evidence carries `Repair round`, `Executor: fixer-max`, `Agent ID`, `Repair hypothesis`, and on an unchanged hypothesis `Falsifying evidence` plus `Falsifies prior hypothesis`.
  - `gdd-finding-state PLAN repair-result FINDING_ID FIXER_REPORT`.
  - `gdd-finding-state PLAN repair-finish FINDING_ID EVIDENCE_FILE`. Evidence carries `Repair round`, `Agent ID`, `Repair head`, `Replay status: VERIFIED|FAILED`, `Replay evidence`.
  - `gdd-finding-state PLAN guard SLICE TARGET_STATE`.
  - `gdd-finding-state PLAN digest OUTPUT_FILE`. Appends `## Advisor consultations`.
- Removed: `repair-entry` command, `Executor: fixer`, `Affected slices`, `Replay full lifecycle`, `Final-wave findings`, origin `Fixer` handling.

- [ ] **Step 1: Rewrite the test file helpers and origin coverage**

Edit `gdd-finding-state.test.sh`:

1. In `make_fixture` (line 42-68) change the result file so the implementer accept passes Task 1's status check. Replace `printf 'Status: PASS\n' >"$RESULT"` with:

```bash
printf 'Status: DONE\n' >"$RESULT"
```

Apply the same change in `make_two_slice_fixture` (line 70-102).

2. In `complete_obligation` (line 117-153) replace the case entry `slice-*-security) origin='Security Reviewer' ;;` with:

```bash
    slice-*-review) origin='Task Reviewer' ;;
    feature-security-review) origin='Security Reviewer' ;;
```

The reviewer branch must call `report` with an empty findings directory so E3 yields PASS. Keep the existing `report` call shape (`"$FINDING_STATE" "$PLAN" report "$scope" "$origin" "$ROLE_REPORT" "$EMPTY_DIR"`) for those origins.

3. Replace `claim_origin_obligation` (line 155-183) with:

```bash
claim_origin_obligation() {
  local origin=$1
  complete_obligation slice-1-implementer implementer
  if [ "$origin" = 'Task Reviewer' ]; then
    claim slice-1-review task-reviewer
    return
  fi
  complete_obligation slice-1-review task-reviewer
  case "$origin" in
    Cleaner) claim slice-1-cleaner cleaner ;;
    Architect)
      complete_obligation slice-1-cleaner cleaner
      claim slice-1-architect architect
      ;;
    Hardener)
      complete_obligation slice-1-cleaner cleaner
      complete_obligation slice-1-architect architect
      claim slice-1-hardener hardener
      ;;
    QA)
      complete_obligation slice-1-cleaner cleaner
      complete_obligation slice-1-architect architect
      complete_obligation slice-1-hardener hardener
      claim slice-1-qa e2e-runner
      ;;
    *) record_fail "unknown origin for fixture: $origin" ;;
  esac
}
```

4. Change `origin_obligation_id` (line 261-270) so `'Task Reviewer'` maps to `slice-1-review` and delete the `'Security Reviewer'` mapping to `slice-1-security`.

5. Change the origin loop (line 284-300) to `for origin in 'Task Reviewer' Cleaner Architect Hardener QA; do`. The slug for the fixture name is `$(printf '%s' "$origin" | tr 'A-Z ' 'a-z-')`.

6. In the branch-origin test (line 364-383), the supplement test (385-426), and the parked-wake test (428-479), replace every `'slice-1-security security-reviewer'` list entry with `'slice-1-review task-reviewer'` placed directly after the implementer entry, and add `'feature-security-review security-reviewer'` after `'feature-branch-review branch-reviewer'` wherever the feature obligations are walked.

7. In the blocked-boundary test (line 495-532) add `complete_obligation slice-1-review task-reviewer` after the implementer completion, and replace the `events/event-8/metadata.tsv` assertion with a search that does not depend on event numbering:

```bash
if grep -lq $'blocking-boundary\tslice-1-architect' "$WORKSPACE"/workflow-v1/events/*/metadata.tsv; then
  record_pass 'BLOCKED metadata records the dependency boundary'
else
  record_fail 'BLOCKED metadata records the dependency boundary'
fi
```

8. Delete the feature-repair-invalidation test (line 534-697). Step 2 adds its replacement.

- [ ] **Step 2: Add the new tests**

The existing helpers have these shapes. Use them as they are: `write_report OUTPUT ORIGIN [yes|no]` always writes `Severity claim: Important`, `write_role_report OUTPUT FINDING_COUNT [STATUS]`, `write_ruling OUTPUT DISPOSITION` (writes a readable `Fable result` file), `claim OBLIGATION ACTOR` (records pass or fail and never aborts), `expect_failure LABEL CMD...`, `expect_contains LABEL FILE NEEDLE` (the second argument is a file path, not a string), `record_pass LABEL`, `record_fail LABEL`. Finding files in a findings directory are numbered `1.md`, `2.md`, and so on.

Append before the final summary lines of `gdd-finding-state.test.sh`. Helpers first:

```bash
make_round_fixture() {
  make_fixture "$1"
  FINDINGS_DIR="$TEST_ROOT/$1-findings"
  EMPTY_DIR="$TEST_ROOT/$1-empty"
  ROLE_REPORT="$TEST_ROOT/$1-role-report.md"
  REVIEW="$TEST_ROOT/$1-review.md"
  RULING="$TEST_ROOT/$1-ruling.md"
  CONSULT="$TEST_ROOT/$1-consult.md"
  REPAIR="$TEST_ROOT/$1-repair-start.md"
  FINISH="$TEST_ROOT/$1-repair-finish.md"
  FIXER_REPORT="$TEST_ROOT/$1-fixer-report.md"
  OUT="$TEST_ROOT/$1-out.txt"
  rm -rf "$FINDINGS_DIR" "$EMPTY_DIR"
  mkdir -p "$FINDINGS_DIR" "$EMPTY_DIR"
  printf 'Status: FIXED\n' >"$FIXER_REPORT"
}

write_finding() {
  local output=$1 origin=$2 severity=$3 summary=$4
  printf '%s\n' \
    "Origin role: $origin" \
    "Severity claim: $severity" \
    'Blocking claim: yes' \
    "Observed failure: $summary" \
    'Evidence: reports/review.md' \
    'Violated authority: approved design' \
    'Assumptions: The journal is authoritative.' \
    'Failure scenario: A lifecycle role advances without adjudication.' \
    'Proposed repair: Fix the reported code.' \
    'Repair effects: The re-review confirms the fix.' >"$output"
}

write_repair_start() {
  local output=$1 round=$2 executor=$3 agent=$4 hypothesis=$5
  printf 'Repair round: %s\nExecutor: %s\nAgent ID: %s\nRepair hypothesis: %s\n' \
    "$round" "$executor" "$agent" "$hypothesis" >"$output"
}

write_repair_finish() {
  local output=$1 round=$2 agent=$3 status=$4 evidence=$5
  printf 'Repair round: %s\nExecutor: fixer-max\nAgent ID: %s\nRepair head: %s\nReplay status: %s\nReplay evidence: %s\n' \
    "$round" "$agent" "$(git -C "$REPO" rev-parse HEAD)" "$status" "$evidence" >"$output"
}

write_repairing() {
  local output=$1 through=$2
  printf 'Disposition: REPAIRING\nRepair hypothesis: the handler drops the error\nRepair base: %s\nReplay through: %s\n' \
    "$(git -C "$REPO" rev-parse HEAD)" "$through" >"$output"
}

write_resolved() {
  local output=$1 evidence=$2
  printf 'Disposition: RESOLVED\nResolution evidence: %s\n' "$evidence" >"$output"
}

write_consult() {
  local output=$1 ids=$2 case_id=$3 decision=$4
  printf '%s\n' \
    "Finding IDs: $ids" \
    "Case: $case_id" \
    'Problem: the reviewer flagged an unchecked error' \
    'Verdict: the finding is real' \
    'Recommendation: fix in this round' \
    'Basis: the handler returns before logging' \
    'Risks and assumptions: NOT GIVEN' \
    'Flip condition: NOT GIVEN' \
    'Forward consult gates: NOT GIVEN' \
    "Decision: $decision" \
    'Reason: the fix is one line' \
    'Cost if wrong: a silent retry loop' \
    'Controller action: dispatch fixer-max' >"$output"
}

assert_next() {
  local label=$1 expected=$2
  "$WORKFLOW_STATE" "$PLAN" next >"$OUT" 2>&1 || true
  expect_contains "$label" "$OUT" "$expected"
}

assert_status() {
  local label=$1 expected=$2
  "$WORKFLOW_STATE" "$PLAN" status >"$OUT" 2>&1 || true
  expect_contains "$label" "$OUT" "$expected"
}
```

Then the tests:

```bash
make_round_fixture scope-origin
complete_obligation slice-1-implementer implementer
claim slice-1-review task-reviewer
write_role_report "$ROLE_REPORT" 1 FAIL
write_finding "$FINDINGS_DIR/1.md" 'Security Reviewer' Important 'token in log'
expect_failure 'a Security Reviewer finding cannot use slice scope' \
  "$FINDING_STATE" "$PLAN" report 1 'Security Reviewer' "$ROLE_REPORT" "$FINDINGS_DIR"
write_finding "$FINDINGS_DIR/1.md" Cleaner Important 'duplicate helper'
expect_failure 'a Cleaner finding cannot use feature scope' \
  "$FINDING_STATE" "$PLAN" report feature Cleaner "$ROLE_REPORT" "$FINDINGS_DIR"

make_round_fixture review-round
complete_obligation slice-1-implementer implementer
claim slice-1-review task-reviewer
write_finding "$FINDINGS_DIR/1.md" 'Task Reviewer' Important 'unchecked error'
write_role_report "$ROLE_REPORT" 1 FAIL
"$FINDING_STATE" "$PLAN" report 1 'Task Reviewer' "$ROLE_REPORT" "$FINDINGS_DIR" >"$OUT"
expect_contains 'the review report creates GDD-F0001' "$OUT" GDD-F0001
assert_status 'a Task Reviewer Important finding holds the review' $'slice-1-review\tPENDING'
claim finding-GDD-F0001-consult-1 controller
write_consult "$CONSULT" GDD-F0001 C1 FIX_NOW
"$FINDING_STATE" "$PLAN" consult GDD-F0001 "$CONSULT"
cat "$WORKSPACE"/workflow-v1/events/*/metadata.tsv >"$OUT"
expect_contains 'consult records a FindingConsultRecorded event' "$OUT" $'result-kind\tFindingConsultRecorded'
claim finding-GDD-F0001-dispose controller
write_repairing "$RULING" re-review
"$FINDING_STATE" "$PLAN" transition GDD-F0001 REPAIRING "$RULING"
claim finding-GDD-F0001-repair-start-1 controller
write_repair_start "$REPAIR" 1 fixer fixer-1 'guard the error path'
expect_failure 'Executor: fixer is rejected' \
  "$FINDING_STATE" "$PLAN" repair-start GDD-F0001 "$REPAIR"
write_repair_start "$REPAIR" 1 fixer-max fixer-1 'guard the error path'
"$FINDING_STATE" "$PLAN" repair-start GDD-F0001 "$REPAIR"
claim finding-GDD-F0001-repair-result-1 fixer-max
"$FINDING_STATE" "$PLAN" repair-result GDD-F0001 "$FIXER_REPORT"
assert_next 'repair-result frees the review for re-review' slice-1-review
claim slice-1-review re-reviewer
write_role_report "$REVIEW" 0 PASS
"$FINDING_STATE" "$PLAN" report 1 Re-reviewer "$REVIEW" "$EMPTY_DIR"
assert_next 'a re-review with an open owned finding accepts as FAIL' finding-GDD-F0001-repair-finish-1
claim finding-GDD-F0001-repair-finish-1 controller
write_repair_finish "$FINISH" 1 fixer-1 VERIFIED "$REVIEW"
"$FINDING_STATE" "$PLAN" repair-finish GDD-F0001 "$FINISH"
claim finding-GDD-F0001-resolve controller
write_resolved "$RULING" "$FINISH"
"$FINDING_STATE" "$PLAN" transition GDD-F0001 RESOLVED "$RULING"
claim slice-1-review re-reviewer
"$FINDING_STATE" "$PLAN" report 1 Re-reviewer "$REVIEW" "$EMPTY_DIR"
assert_next 'the closing review PASS releases the Cleaner' slice-1-cleaner

make_round_fixture round-cap
complete_obligation slice-1-implementer implementer
claim slice-1-review task-reviewer
write_finding "$FINDINGS_DIR/1.md" 'Task Reviewer' Critical 'unbounded retry'
write_role_report "$ROLE_REPORT" 1 FAIL
"$FINDING_STATE" "$PLAN" report 1 'Task Reviewer' "$ROLE_REPORT" "$FINDINGS_DIR" >/dev/null
claim finding-GDD-F0001-dispose controller
write_repairing "$RULING" re-review
"$FINDING_STATE" "$PLAN" transition GDD-F0001 REPAIRING "$RULING"
write_role_report "$REVIEW" 0 FAIL
for round in 1 2 3 4 5; do
  claim "finding-GDD-F0001-repair-start-$round" controller
  write_repair_start "$REPAIR" "$round" fixer-max "fixer-$round" "attempt $round"
  "$FINDING_STATE" "$PLAN" repair-start GDD-F0001 "$REPAIR"
  claim "finding-GDD-F0001-repair-result-$round" fixer-max
  "$FINDING_STATE" "$PLAN" repair-result GDD-F0001 "$FIXER_REPORT"
  claim slice-1-review re-reviewer
  "$FINDING_STATE" "$PLAN" report 1 Re-reviewer "$REVIEW" "$EMPTY_DIR"
  claim "finding-GDD-F0001-repair-finish-$round" controller
  write_repair_finish "$FINISH" "$round" "fixer-$round" FAILED "$REVIEW"
  "$FINDING_STATE" "$PLAN" repair-finish GDD-F0001 "$FINISH"
done
assert_next 'five failed rounds reopen dispose' finding-GDD-F0001-dispose
claim finding-GDD-F0001-dispose controller
write_repair_start "$REPAIR" 6 fixer-max fixer-6 'attempt 6'
expect_failure 'a sixth slice round is rejected' \
  "$FINDING_STATE" "$PLAN" repair-start GDD-F0001 "$REPAIR"
"$FINDING_STATE" "$PLAN" repair-start GDD-F0001 "$REPAIR" >"$OUT" 2>&1 || true
expect_contains 'the cap failure names the cap' "$OUT" 'slice round cap reached'
write_ruling "$RULING" PARKED
"$FINDING_STATE" "$PLAN" transition GDD-F0001 PARKED "$RULING"

make_round_fixture downstream-round
complete_obligation slice-1-implementer implementer
complete_obligation slice-1-review task-reviewer
claim slice-1-cleaner cleaner
write_finding "$FINDINGS_DIR/1.md" Cleaner Minor 'duplicate helper'
write_role_report "$ROLE_REPORT" 1 PASS
"$FINDING_STATE" "$PLAN" report 1 Cleaner "$ROLE_REPORT" "$FINDINGS_DIR" >/dev/null
claim finding-GDD-F0001-dispose controller
write_repairing "$RULING" downstream
"$FINDING_STATE" "$PLAN" transition GDD-F0001 REPAIRING "$RULING"
claim finding-GDD-F0001-repair-start-1 controller
write_repair_start "$REPAIR" 1 fixer-max fixer-1 'merge the helpers'
"$FINDING_STATE" "$PLAN" repair-start GDD-F0001 "$REPAIR"
claim finding-GDD-F0001-repair-result-1 fixer-max
"$FINDING_STATE" "$PLAN" repair-result GDD-F0001 "$FIXER_REPORT"
"$FINDING_STATE" "$PLAN" guard 1 verifying-hardener
expect_failure 'a downstream finding permits only the next worker' \
  "$FINDING_STATE" "$PLAN" guard 1 verifying-qa
complete_obligation slice-1-architect architect
assert_next 'the Architect PASS readies the downstream finish' finding-GDD-F0001-repair-finish-1
claim finding-GDD-F0001-repair-finish-1 controller
write_repair_finish "$FINISH" 1 fixer-1 VERIFIED "$ROLE_REPORT"
"$FINDING_STATE" "$PLAN" repair-finish GDD-F0001 "$FINISH"
claim finding-GDD-F0001-resolve controller
write_resolved "$RULING" "$FINISH"
"$FINDING_STATE" "$PLAN" transition GDD-F0001 RESOLVED "$RULING"

make_round_fixture feature-closing
complete_obligation slice-1-implementer implementer
complete_obligation slice-1-review task-reviewer
complete_obligation slice-1-cleaner cleaner
complete_obligation slice-1-architect architect
complete_obligation slice-1-hardener hardener
complete_obligation slice-1-qa e2e-runner
claim feature-branch-review branch-reviewer
write_finding "$FINDINGS_DIR/1.md" 'Branch Reviewer' Minor 'drifted naming'
write_role_report "$ROLE_REPORT" 1 FAIL
"$FINDING_STATE" "$PLAN" report feature 'Branch Reviewer' "$ROLE_REPORT" "$FINDINGS_DIR" >/dev/null
claim finding-GDD-F0001-dispose controller
write_repairing "$RULING" re-review
"$FINDING_STATE" "$PLAN" transition GDD-F0001 REPAIRING "$RULING"
claim feature-security-review security-reviewer
write_finding "$FINDINGS_DIR/1.md" 'Security Reviewer' Critical 'token in log'
"$FINDING_STATE" "$PLAN" report feature 'Security Reviewer' "$ROLE_REPORT" "$FINDINGS_DIR" >/dev/null
claim finding-GDD-F0002-dispose controller
"$FINDING_STATE" "$PLAN" transition GDD-F0002 REPAIRING "$RULING"
claim finding-GDD-F0001-repair-start-1 controller
write_repair_start "$REPAIR" 1 fixer-max fixer-1 'rename and redact'
"$FINDING_STATE" "$PLAN" repair-start GDD-F0001 "$REPAIR"
claim finding-GDD-F0002-repair-start-1 controller
"$FINDING_STATE" "$PLAN" repair-start GDD-F0002 "$REPAIR"
claim finding-GDD-F0001-repair-result-1 fixer-max
"$FINDING_STATE" "$PLAN" repair-result GDD-F0001 "$FIXER_REPORT"
claim finding-GDD-F0002-repair-result-1 fixer-max
"$FINDING_STATE" "$PLAN" repair-result GDD-F0002 "$FIXER_REPORT"
write_role_report "$REVIEW" 0 PASS
claim feature-branch-review branch-reviewer
"$FINDING_STATE" "$PLAN" report feature 'Branch Reviewer' "$REVIEW" "$EMPTY_DIR"
claim finding-GDD-F0001-repair-finish-1 controller
write_repair_finish "$FINISH" 1 fixer-1 VERIFIED "$REVIEW"
"$FINDING_STATE" "$PLAN" repair-finish GDD-F0001 "$FINISH"
claim finding-GDD-F0001-resolve controller
write_resolved "$RULING" "$FINISH"
"$FINDING_STATE" "$PLAN" transition GDD-F0001 RESOLVED "$RULING"
claim feature-security-review security-reviewer
"$FINDING_STATE" "$PLAN" report feature 'Security Reviewer' "$REVIEW" "$EMPTY_DIR"
claim finding-GDD-F0002-repair-finish-1 controller
"$FINDING_STATE" "$PLAN" repair-finish GDD-F0002 "$FINISH"
claim finding-GDD-F0002-resolve controller
"$FINDING_STATE" "$PLAN" transition GDD-F0002 RESOLVED "$RULING"
claim feature-branch-review branch-reviewer
"$FINDING_STATE" "$PLAN" report feature 'Branch Reviewer' "$REVIEW" "$EMPTY_DIR"
claim feature-security-review security-reviewer
"$FINDING_STATE" "$PLAN" report feature 'Security Reviewer' "$REVIEW" "$EMPTY_DIR"
assert_next 'both closing reviews PASS release the digest' feature-findings-digest
expect_failure 'a second feature round is not claimable' \
  "$WORKFLOW_STATE" "$PLAN" claim finding-GDD-F0002-repair-start-2 controller "$DISPATCH"
```

Add one assertion to the supplement test (line 385-426) directly before the `DISMISSED` transition: claim `"finding-$incomplete_id-consult-1"` as `controller`, write `write_consult "$TEST_ROOT/supplement-consult.md" "$incomplete_id" C5 NO_FIX`, run `"$FINDING_STATE" "$PLAN" consult "$incomplete_id" "$TEST_ROOT/supplement-consult.md"`. The test names that finding `$incomplete_id` (line 401), not a literal ID. Move the helper definitions above the supplement test so they are defined when it runs. After the digest is written, add:

```bash
expect_contains 'the digest lists the consultation' "$DIGEST" '## Advisor consultations'
expect_contains 'the digest lists the consultation case' "$DIGEST" 'Case: C5'
```

- [ ] **Step 3: Run the test to see it fail**

Run: `bash /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh`
Expected: FAIL. The first failure is the origin loop for `Task Reviewer` (`unknown finding origin`), then `consult` (`unknown command`).

- [ ] **Step 4: Rewrite validation in `gdd-finding-state`**

Replace the usage block (line 10-24) with:

```bash
usage() {
  cat >&2 <<'EOF'
usage:
  gdd-finding-state PLAN_FILE init
  gdd-finding-state PLAN_FILE report SCOPE ORIGIN ROLE_REPORT FINDINGS_DIR [FINAL_SUITE_REPORT]
  gdd-finding-state PLAN_FILE supplement FINDING_ID REPORT_FILE
  gdd-finding-state PLAN_FILE transition FINDING_ID STATE EVIDENCE_FILE
  gdd-finding-state PLAN_FILE consult FINDING_ID CONSULT_FILE
  gdd-finding-state PLAN_FILE repair-start FINDING_ID EVIDENCE_FILE
  gdd-finding-state PLAN_FILE repair-result FINDING_ID FIXER_REPORT
  gdd-finding-state PLAN_FILE repair-finish FINDING_ID EVIDENCE_FILE
  gdd-finding-state PLAN_FILE guard SLICE TARGET_STATE
  gdd-finding-state PLAN_FILE digest OUTPUT_FILE
EOF
  exit 2
}
```

Add after the existing readonly constants:

```bash
readonly CONSULT_FIELDS='Finding IDs|Case|Problem|Verdict|Recommendation|Basis|Risks and assumptions|Flip condition|Forward consult gates|Decision|Reason|Cost if wrong|Controller action'
```

Replace `validate_scope_origin` (line 56-73):

```bash
validate_scope_origin() {
  scope=$1
  origin=$2
  case "$origin" in
    'Task Reviewer'|Re-reviewer|Cleaner|Architect|Hardener|QA|'Branch Reviewer'|'Security Reviewer') ;;
    *) fail "unknown finding origin: $origin" ;;
  esac
  if [ "$scope" = feature ]; then
    case "$origin" in
      'Branch Reviewer'|'Security Reviewer') ;;
      *) fail "feature findings must originate from Branch Reviewer or Security Reviewer: $origin" ;;
    esac
    return
  fi
  case "$scope" in
    ''|*[!0-9]*|0) fail "finding scope must be a positive slice number or feature: $scope" ;;
  esac
  case "$origin" in
    'Branch Reviewer'|'Security Reviewer') fail "$origin findings must use feature scope" ;;
  esac
}
```

Replace `validate_replay_origin` (line 200-202):

```bash
validate_replay_origin() {
  case "$1" in
    re-review|downstream) ;;
    *) fail "Replay through must be re-review or downstream: $1" ;;
  esac
}
```

Delete `validate_affected_slices` (line 204-221) and `validate_final_wave_findings` (line 223-243).

In `validate_transition_evidence` (line 245-314) replace the `REPAIRING` branch (line 252-270) with:

```bash
    REPAIRING)
      require_complete_report "$finding_id"
      hypothesis=$(field_value 'Repair hypothesis' "$evidence_file")
      repair_base=$(field_value 'Repair base' "$evidence_file")
      replay_through=$(field_value 'Replay through' "$evidence_file")
      [ -n "$hypothesis" ] || fail 'REPAIRING requires Repair hypothesis'
      [ -n "$repair_base" ] || fail 'REPAIRING requires Repair base'
      git -C "$repo_root" cat-file -e "$repair_base^{commit}" 2>/dev/null \
        || fail "Repair base is not an existing commit: $repair_base"
      validate_replay_origin "$replay_through"
      if [ "$replay_through" = downstream ]; then
        case "$(finding_origin "$finding_id")" in
          Cleaner|Architect|Hardener|QA) ;;
          *) fail 'Replay through: downstream requires a Cleaner, Architect, Hardener, or QA finding' ;;
        esac
      fi
      ;;
```

Keep the variable names the original branch used if they differ from the ones above (`repo_root` is the repository root variable already used by the `Repair base` check). Replace the terminal branch (line 271-300) with:

```bash
    DEFERRED|DISMISSED|PARKED|BLOCKED)
      require_complete_report "$finding_id"
      [ "$(field_value Disposition "$evidence_file")" = "$target_state" ] \
        || fail "$target_state requires matching Disposition"
      for terminal_field in Ruling 'Cost if wrong' 'Wake condition'; do
        [ -n "$(field_value "$terminal_field" "$evidence_file")" ] \
          || fail "$target_state requires $terminal_field"
      done
      if [ "$target_state" != DEFERRED ]; then
        fable_value=$(field_value 'Fable result' "$evidence_file")
        [ -n "$fable_value" ] || fail "$target_state requires Fable result"
        case "$fable_value" in
          'UNAVAILABLE: '?*)
            if [ "$target_state" != BLOCKED ]; then
              user_authority=$(field_value 'User authority' "$evidence_file")
              [ -n "$user_authority" ] || fail "$target_state without Fable requires User authority"
              require_readable_file "$user_authority" 'User authority'
            fi
            ;;
          UNAVAILABLE:*) fail 'Fable result UNAVAILABLE needs a reason' ;;
          *) require_readable_file "$fable_value" 'Fable result' ;;
        esac
      fi
      if [ "$target_state" = BLOCKED ]; then
        blocking_boundary=$(field_value 'Blocked boundary' "$evidence_file")
        [ -n "$blocking_boundary" ] || fail 'BLOCKED requires Blocked boundary'
      fi
      ;;
```

Keep the original BLOCKED boundary validation body if it checks more than non-empty (for example that the boundary names an obligation). Copy that check into the block above unchanged.

Add these helpers after `repair_event_for_round` (line 347-357):

```bash
scope_finding_ids() {
  awk -F '\t' -v expected_scope="$1" '$2 == expected_scope { seen[$1] = 1 } END { for (id in seen) print id }' "$ledger" | sort
}

scope_max_round() {
  local scope=$1 other_id round max_round=0
  for other_id in $(scope_finding_ids "$scope"); do
    for round in 1 2 3 4 5; do
      [ -n "$(repair_event_for_round "$other_id" repair-start "$round")" ] || continue
      [ "$round" -le "$max_round" ] || max_round=$round
    done
  done
  printf '%s\n' "$max_round"
}

scope_round_is_open() {
  local scope=$1 round=$2 other_id
  for other_id in $(scope_finding_ids "$scope"); do
    [ -n "$(repair_event_for_round "$other_id" repair-start "$round")" ] || continue
    [ -n "$(repair_event_for_round "$other_id" repair-finish "$round")" ] || return 0
  done
  return 1
}

scope_next_round() {
  local scope=$1 max_round
  max_round=$(scope_max_round "$scope")
  if [ "$max_round" -gt 0 ] && scope_round_is_open "$scope" "$max_round"; then
    printf '%s\n' "$max_round"
  else
    printf '%s\n' $((max_round + 1))
  fi
}
```

`$ledger` is the findings ledger path variable the script already uses (the `findings.tsv` under the workspace). Use that exact variable name.

Replace `validate_repair_start` (line 359-398):

```bash
validate_repair_start() {
  finding_id=$1
  evidence_file=$2
  [ "$(latest_lifecycle_state "$finding_id")" = REPAIRING ] \
    || fail 'repair-start requires a REPAIRING finding'
  require_readable_file "$evidence_file" 'repair-start evidence'
  scope=$(finding_scope "$finding_id")
  origin=$(finding_origin "$finding_id")
  round=$(field_value 'Repair round' "$evidence_file")
  executor=$(field_value Executor "$evidence_file")
  agent_id=$(field_value 'Agent ID' "$evidence_file")
  hypothesis=$(field_value 'Repair hypothesis' "$evidence_file")
  expected_round=$(scope_next_round "$scope")
  if [ "$scope" = feature ]; then
    [ "$expected_round" -le 1 ] || fail 'feature round cap reached'
  else
    [ "$expected_round" -le 5 ] || fail 'slice round cap reached'
  fi
  [ "$round" = "$expected_round" ] || fail "Repair round must be $expected_round for scope $scope: $round"
  [ -n "$agent_id" ] || fail 'repair-start requires Agent ID'
  [ -n "$hypothesis" ] || fail 'repair-start requires Repair hypothesis'
  case "$executor" in
    fixer-max) ;;
    hardener)
      [ "$origin" = Hardener ] \
        && [ "$(field_value 'Replay through' "$(latest_event_evidence "$finding_id" transition-repairing)")" = downstream ] \
        || fail 'Executor: hardener is allowed only for a Hardener finding with Replay through: downstream'
      ;;
    *) fail "repair-start requires Executor: fixer-max: $executor" ;;
  esac
  previous_start=$(latest_repair_start "$finding_id")
  if [ -n "$previous_start" ] && [ -s "$previous_start" ]; then
    previous_round=$(field_value 'Repair round' "$previous_start")
    [ "$round" -gt "$previous_round" ] || fail 'Repair round must exceed the previous round of this finding'
    previous_finish=$(repair_event_for_round "$finding_id" repair-finish "$previous_round")
    [ -n "$previous_finish" ] && [ -s "$previous_finish" ] \
      || fail 'a new repair round requires the prior repair-finish'
    [ "$(field_value 'Replay status' "$previous_finish")" = FAILED ] \
      || fail 'a new repair round requires the prior repair-finish to be FAILED'
    if [ "$hypothesis" = "$(field_value 'Repair hypothesis' "$previous_start")" ]; then
      falsifying_file=$(field_value 'Falsifying evidence' "$evidence_file")
      require_readable_file "$falsifying_file" 'Falsifying evidence'
      [ -n "$(field_value 'Falsifies prior hypothesis' "$evidence_file")" ] \
        || fail 'an unchanged Repair hypothesis requires Falsifies prior hypothesis'
    fi
  fi
  if find "$findings_dir/$finding_id/events" -name evidence.md -type f -print0 2>/dev/null \
    | xargs -0 grep -Fqx "Agent ID: $agent_id" 2>/dev/null; then
    fail "Agent ID was already used for finding $finding_id: $agent_id"
  fi
}
```

`latest_repair_start`, `latest_event_evidence`, `finding_scope`, `finding_origin`, `latest_lifecycle_state`, and `$findings_dir` are existing helpers and variables in the script. Reuse them. If `latest_repair_start` does not exist, define it as `latest_event_evidence "$1" repair-start`.

Keep `validate_repair_finish` (line 400-424) as is. Delete `rank_for_target` (line 426-436), `rank_for_origin` (line 438-440), and `slice_is_verified` (line 446-450).

- [ ] **Step 5: Rewrite the engine bridge and the reviewer result rule**

Replace `accept_finding_result` (line 467-492) so it exports only the surviving environment: `GDD_FINDING_ID`, `GDD_FINDING_SCOPE`, `GDD_FINDING_ORIGIN`, `GDD_FINDING_STATE`, `GDD_FINDING_EVENT_NAME`, `GDD_REPAIR_ROUND`, `GDD_REPLAY_STATUS`, `GDD_REPLAY_THROUGH`, `GDD_BLOCKING_BOUNDARY`. Delete the `GDD_TARGET_SLICE`, `GDD_AFFECTED_SLICES`, `GDD_REPLAY_FULL_LIFECYCLE`, and `GDD_FINAL_WAVE_FINDINGS` lines. The call to `gdd-workflow-state ... accept-active` stays the same.

Add before `command_report`:

```bash
review_owns_origin() {
  case "$1:$2" in
    'Task Reviewer:Task Reviewer'|'Task Reviewer:Re-reviewer'|'Re-reviewer:Task Reviewer'|'Re-reviewer:Re-reviewer') return 0 ;;
    'Branch Reviewer:Branch Reviewer'|'Security Reviewer:Security Reviewer') return 0 ;;
    *) return 1 ;;
  esac
}

review_result_kind() {
  local scope=$1 origin=$2 role_findings_dir=$3 finding_file severity other_id
  for finding_file in "$role_findings_dir"/*.md; do
    [ -f "$finding_file" ] || continue
    severity=$(field_value 'Severity claim' "$finding_file")
    case "$origin:$severity" in
      'Branch Reviewer:'*|'Security Reviewer:'*) printf 'FAIL\n'; return ;;
      *:Critical|*:Important) printf 'FAIL\n'; return ;;
    esac
  done
  for other_id in $(scope_finding_ids "$scope"); do
    review_owns_origin "$origin" "$(finding_origin "$other_id")" || continue
    case "$(latest_lifecycle_state "$other_id")" in
      REPORTED|REPAIRING) printf 'FAIL\n'; return ;;
    esac
  done
  printf 'PASS\n'
}
```

In `command_report` (line 499-550) replace the `case "$origin:$role_status"` block with:

```bash
  case "$origin" in
    'Task Reviewer'|Re-reviewer|'Branch Reviewer'|'Security Reviewer')
      [ -z "$final_suite_report" ] || usage
      result_kind=$(review_result_kind "$scope" "$origin" "$role_findings_dir")
      GDD_FINDINGS_DIR="$role_findings_dir" "$SCRIPT_DIR/gdd-workflow-state" "$plan" \
        accept-active "$obligation" "$result_kind" "$role_report" >/dev/null
      ;;
    QA)
      case "$role_status" in
        VERIFIED)
          [ -n "$final_suite_report" ] || usage
          GDD_FINDINGS_DIR="$role_findings_dir" "$SCRIPT_DIR/gdd-workflow-state" "$plan" \
            accept-active "$obligation" SliceVerifiedMacro "$role_report" "$final_suite_report" >/dev/null
          ;;
        'NOT VERIFIED')
          GDD_FINDINGS_DIR="$role_findings_dir" "$SCRIPT_DIR/gdd-workflow-state" "$plan" \
            accept-active "$obligation" FAIL "$role_report" >/dev/null
          ;;
        *) fail 'QA report must contain Status: VERIFIED or Status: NOT VERIFIED' ;;
      esac
      ;;
    Hardener)
      case "$role_status" in
        VERIFIED)
          GDD_FINDINGS_DIR="$role_findings_dir" "$SCRIPT_DIR/gdd-workflow-state" "$plan" \
            accept-active "$obligation" PASS "$role_report" >/dev/null
          ;;
        'NOT VERIFIED'|REVERIFY_REQUIRED)
          GDD_FINDINGS_DIR="$role_findings_dir" "$SCRIPT_DIR/gdd-workflow-state" "$plan" \
            accept-active "$obligation" FAIL "$role_report" >/dev/null
          ;;
        *) fail 'Hardener report must contain Status: VERIFIED, NOT VERIFIED, or REVERIFY_REQUIRED' ;;
      esac
      ;;
    *)
      GDD_FINDINGS_DIR="$role_findings_dir" "$SCRIPT_DIR/gdd-workflow-state" "$plan" \
        accept-active "$obligation" PASS "$role_report" >/dev/null
      ;;
  esac
```

Keep the variable names of the original function (`obligation`, `role_report`, `role_findings_dir`, `final_suite_report`, `role_status`) and the trailing block that prints the new finding ids.

Replace `origin_obligation_id` (line 552-563):

```bash
origin_obligation_id() {
  scope=$1
  origin=$2
  case "$origin" in
    'Branch Reviewer') printf 'feature-branch-review\n' ;;
    'Security Reviewer') printf 'feature-security-review\n' ;;
    'Task Reviewer'|Re-reviewer) printf 'slice-%s-review\n' "$scope" ;;
    Cleaner) printf 'slice-%s-cleaner\n' "$scope" ;;
    Architect) printf 'slice-%s-architect\n' "$scope" ;;
    Hardener) printf 'slice-%s-hardener\n' "$scope" ;;
    QA) printf 'slice-%s-qa\n' "$scope" ;;
    *) fail "unknown finding origin: $origin" ;;
  esac
}
```

In `command_transition` (line 577-627) replace the supporting-evidence and environment section (line 588-626) with:

```bash
  fable_file=''
  case "$target_state" in
    DISMISSED|PARKED|BLOCKED)
      fable_value=$(field_value 'Fable result' "$evidence_file")
      case "$fable_value" in
        UNAVAILABLE:*) fable_file=$(field_value 'User authority' "$evidence_file") ;;
        *) fable_file=$fable_value ;;
      esac
      ;;
  esac
  replay_through=''
  blocking_boundary=''
  [ "$target_state" != REPAIRING ] || replay_through=$(field_value 'Replay through' "$evidence_file")
  [ "$target_state" != BLOCKED ] || blocking_boundary=$(field_value 'Blocked boundary' "$evidence_file")
  GDD_FINDING_STATE="$target_state" GDD_FINDING_EVENT_NAME="transition-$(printf '%s' "$target_state" | tr 'A-Z' 'a-z')" \
    GDD_REPLAY_THROUGH="$replay_through" GDD_BLOCKING_BOUNDARY="$blocking_boundary" \
    accept_finding_result "$finding_id" FindingDispositionRecorded "$evidence_file" ${fable_file:+"$fable_file"}
```

Keep the original event-name derivation if it already exists under a different expression that yields `transition-repairing`, `transition-resolved`, and so on. The value must stay `transition-<lowercase state>` because `latest_event_evidence "$finding_id" transition-repairing` depends on it.

- [ ] **Step 6: Add `repair-result`, `consult`, the new guard, and the digest section**

Add after `command_repair_start`:

```bash
command_repair_result() {
  [ $# -eq 2 ] || usage
  finding_id=$1
  fixer_report=$2
  require_workspace
  require_finding "$finding_id"
  require_readable_file "$fixer_report" 'fixer report'
  [ "$(latest_lifecycle_state "$finding_id")" = REPAIRING ] \
    || fail 'repair-result requires a REPAIRING finding'
  start_file=$(latest_repair_start "$finding_id")
  [ -n "$start_file" ] && [ -s "$start_file" ] || fail 'repair-result requires a repair-start'
  round=$(field_value 'Repair round' "$start_file")
  [ -z "$(repair_event_for_round "$finding_id" repair-finish "$round")" ] \
    || fail "repair round $round is already finished"
  replay_through=$(field_value 'Replay through' "$(latest_event_evidence "$finding_id" transition-repairing)")
  GDD_FINDING_STATE=REPAIR_RESULT GDD_FINDING_EVENT_NAME=repair-result \
    GDD_REPAIR_ROUND="$round" GDD_REPLAY_THROUGH="$replay_through" \
    accept_finding_result "$finding_id" RepairAccepted "$fixer_report"
}

validate_consult_file() {
  local finding_id=$1 consult_file=$2 remaining field
  require_readable_file "$consult_file" 'consultation record'
  remaining="$CONSULT_FIELDS|"
  while [ -n "$remaining" ]; do
    field=${remaining%%|*}
    remaining=${remaining#*|}
    [ "$(field_count "$field" "$consult_file")" -eq 1 ] \
      || fail "consultation record must contain exactly one $field"
    [ -n "$(field_value "$field" "$consult_file")" ] \
      || fail "consultation record field is empty: $field"
  done
  case "$(field_value Case "$consult_file")" in
    C1|C2|C3|C4|C5) ;;
    *) fail 'Case must be C1, C2, C3, C4, or C5' ;;
  esac
  case "$(field_value Decision "$consult_file")" in
    FIX_NOW|NO_FIX|PARK|ESCALATE|'USER:'?*) ;;
    *) fail 'Decision must be FIX_NOW, NO_FIX, PARK, ESCALATE, or USER:<ruling>' ;;
  esac
  case ",$(field_value 'Finding IDs' "$consult_file" | tr -d ' ')," in
    *",$finding_id,"*) ;;
    *) fail "Finding IDs does not include $finding_id" ;;
  esac
}

command_consult() {
  [ $# -eq 2 ] || usage
  finding_id=$1
  consult_file=$2
  require_workspace
  require_finding "$finding_id"
  validate_consult_file "$finding_id" "$consult_file"
  case "$(latest_lifecycle_state "$finding_id")" in
    REPORTED|REPAIRING) ;;
    *) fail "consult requires a REPORTED or REPAIRING finding: $finding_id" ;;
  esac
  obligation=$(active_obligation)
  case "$obligation" in
    "finding-$finding_id-consult-"[1-9]) ;;
    *) fail "consult requires an active consult claim for $finding_id: ${obligation:-none}" ;;
  esac
  GDD_FINDING_STATE=CONSULT GDD_FINDING_EVENT_NAME="consult-${obligation##*-consult-}" \
    accept_finding_result "$finding_id" FindingConsultRecorded "$consult_file"
}
```

`field_count`, `require_finding`, `require_workspace`, and `active_obligation` are existing helpers. If `field_count` does not exist, define it as `grep -c "^$1: " "$2" || true` guarded so it prints `0` on no match.

Replace `command_guard` (line 655-689):

```bash
downstream_target() {
  local finding_id=$1 slice=$2 origin worker status
  origin=$(finding_origin "$finding_id")
  for worker in cleaner architect hardener qa; do
    case "$origin:$worker" in
      Architect:cleaner|Hardener:cleaner|Hardener:architect|QA:cleaner|QA:architect|QA:hardener) continue ;;
    esac
    status=$(awk -F '\t' -v obligation="slice-$slice-$worker" '$1 == obligation { print $2; exit }' "$status_file")
    [ "$status" != COMPLETE ] || continue
    case "$worker" in
      cleaner) printf 'verifying-architect\n' ;;
      architect) printf 'verifying-hardener\n' ;;
      hardener) printf 'verifying-qa\n' ;;
      qa) printf 'verified\n' ;;
    esac
    return
  done
  fail "finding $finding_id has no downstream worker left in slice $slice"
}

command_guard() {
  [ $# -eq 2 ] || usage
  slice=$1
  target=$2
  case "$slice" in ''|*[!0-9]*|0) fail "slice number must be a positive integer: $slice" ;; esac
  case "$target" in
    verifying-cleaner|verifying-architect|verifying-hardener|verifying-qa|verified) ;;
    *) fail "unknown lifecycle target: $target" ;;
  esac
  require_workspace
  "$SCRIPT_DIR/gdd-workflow-state" "$plan" status >/dev/null
  status_file="$workspace/workflow-v1/projections/status.tsv"
  for finding_id in $(scope_finding_ids "$slice"); do
    latest_state=$(latest_lifecycle_state "$finding_id")
    case "$latest_state" in
      REPORTED|BLOCKED) fail "finding $finding_id in $latest_state blocks slice $slice" ;;
      REPAIRING)
        [ "$(field_value 'Replay through' "$(latest_event_evidence "$finding_id" transition-repairing)")" = downstream ] \
          || fail "finding $finding_id is REPAIRING and holds slice $slice at its review"
        permitted=$(downstream_target "$finding_id" "$slice")
        [ "$target" = "$permitted" ] \
          || fail "finding $finding_id permits only $permitted while it is REPAIRING"
        ;;
    esac
  done
}
```

`$workspace` is the workspace path variable `require_workspace` sets. Use the script's real name for it.

Delete `command_repair_entry` (line 691-725).

In `command_digest` (line 727-778) change the per-finding `Fable` line to print `NOT REQUIRED` when the field is empty (`"${fable:-NOT REQUIRED}"` with the variable name the function already uses), and add before the final write of the output file:

```bash
    printf '\n## Advisor consultations\n\n'
    consult_number=0
    for finding_id in $(awk -F '\t' '{ seen[$1] = 1 } END { for (id in seen) print id }' "$ledger" | sort); do
      for consult_dir in $(find "$findings_dir/$finding_id/events" -mindepth 1 -maxdepth 1 -type d -name '*-consult-*' 2>/dev/null | sort); do
        consult_number=$((consult_number + 1))
        consult_file="$consult_dir/evidence.md"
        printf '%s. `%s`\n' "$consult_number" "$finding_id"
        printf '   - Finding IDs: %s\n' "$(field_value 'Finding IDs' "$consult_file")"
        printf '   - Case: %s\n' "$(field_value Case "$consult_file")"
        printf '   - Decision: %s\n' "$(field_value Decision "$consult_file")"
        printf '   - Reason: %s\n' "$(field_value Reason "$consult_file")"
        printf '   - Cost if wrong: %s\n\n' "$(field_value 'Cost if wrong' "$consult_file")"
      done
    done
    [ "$consult_number" -gt 0 ] || printf 'None.\n'
```

Confirm the finding events directory layout the script writes (`findings/<id>/events/<seq>-<event-name>/evidence.md`) with `grep -n 'events' gdd-finding-state | head` before relying on the `-name '*-consult-*'` match, and adjust the glob to the real naming if it differs.

Replace the dispatch (line 789-800):

```bash
case "$command" in
  init) command_init "$@" ;;
  report) command_report "$@" ;;
  supplement) command_supplement "$@" ;;
  transition) command_transition "$@" ;;
  consult) command_consult "$@" ;;
  repair-start) command_repair_start "$@" ;;
  repair-result) command_repair_result "$@" ;;
  repair-finish) command_repair_finish "$@" ;;
  guard) command_guard "$@" ;;
  digest) command_digest "$@" ;;
  *) usage ;;
esac
```

- [ ] **Step 7: Verify nothing references the deleted names**

Run:

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts && grep -n 'repair-entry\|repair_entry\|Affected slices\|affected_slices\|final_wave\|Final-wave\|rank_for\|slice_is_verified\|TARGET_SLICE\|REPLAY_FULL' gdd-finding-state gdd-finding-state.test.sh
```

Expected: no output.

- [ ] **Step 8: Run the finding-state test until green**

Run: `bash /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh`
Expected: PASS for every test. Also run the workflow-state test and confirm it is still green:

Run: `bash /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership && git add skills/gauntlet-driven-development/scripts/gdd-finding-state skills/gauntlet-driven-development/scripts/gdd-finding-state.test.sh && git commit -m "feat(gdd): validate fix rounds, consultations, and reviewer origins"
```

### Task 4: Slice-state projection for the review stage

**Files:**
- Modify: `skills/gauntlet-driven-development/scripts/gdd-slice-state` (usage 6-28, delete `feature_repair_affected_slices` 41-55, case block 107-151, state parse 173-184, delete repair-entry call 186-194 and the verifying-cleaner active-claim block 196-214, transitions 225-242, accept case 244-281, delete `required_origin` check 283-288)
- Test: `skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh`

**Interfaces:**
- Consumes: `gdd-workflow-state PLAN accept-active OBLIGATION KIND EVIDENCE...`, `gdd-workflow-state PLAN project`, `gdd-workflow-state PLAN status` (prints `Active claim: <id>` and the `<obligation>\t<status>` rows), the Task 1 projection map `ACCEPT:slice-N-review -> VERIFYING: CLEANER`, and Task 3 `gdd-finding-state` commands in the test.
- Produces the states the skill calls: `implementing`, `reviewing IMPLEMENTER_REPORT`, `verifying-cleaner REVIEW_REPORT FINDINGS_DIR`, `verifying-architect CLEANER_REPORT FINDINGS_DIR`, `verifying-hardener ARCHITECT_REPORT FINDINGS_DIR`, `verifying-qa HARDENER_REPORT FINDINGS_DIR`, `verified QA_REPORT FINAL_SUITE_REPORT FINDINGS_DIR`.
- Removed: `verifying-security`, `repairing`, the `Implementer or Fixer` evidence label, `Status: IMPLEMENTED`.

- [ ] **Step 1: Rewrite the slice-state test**

Edit `gdd-slice-state.test.sh`:

1. Fixture files (around line 60-80): change the implementer fixture to `printf 'Status: DONE\n' >"$IMPLEMENTER"`. Delete the `SECURITY` (`Status: CLEAN`) and `FIXER` (`Status: FIXED`) fixtures. Add:

```bash
REVIEW="$TEST_ROOT/review.md"
printf 'Status: PASS\nFinding count: 0\n' >"$REVIEW"
REVIEW_FAIL="$TEST_ROOT/review-fail.md"
printf 'Status: FAIL\nFinding count: 1\n' >"$REVIEW_FAIL"
FIXER_REPORT="$TEST_ROOT/fixer-report.md"
printf 'Status: FIXED\n' >"$FIXER_REPORT"
REVIEW_FINDINGS="$TEST_ROOT/review-findings"
mkdir -p "$REVIEW_FINDINGS"
cat >"$REVIEW_FINDINGS/1.md" <<'EOF'
Origin role: Task Reviewer
Severity claim: Important
Blocking claim: yes
Observed failure: the handler swallows the error
Evidence: src/handler.sh:12
Violated authority: plan task 1
Assumptions: none
Failure scenario: a failed write reports success
Proposed repair: return the error
Repair effects: none
EOF
```

Keep the field order and names the existing zero-findings fixtures in this file use. If the existing fixtures name the ten fields differently, copy their exact names.

2. Authority lifecycle (line 86-110): after `implementing`, insert:

```bash
expect_failure 'reviewing requires a DONE implementer report' \
  "$SLICE_STATE" "$PLAN" 1 reviewing "$TEST_ROOT/status-implemented.md"
"$SLICE_STATE" "$PLAN" 1 reviewing "$IMPLEMENTER"
expect_contains 'REVIEWING is projected' "$TASKS" '**Slice state:** [~] REVIEWING'
expect_failure 'verifying-cleaner without a review claim fails' \
  "$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$REVIEW" "$ZERO_FINDINGS_DIR"
claim slice-1-review task-reviewer
"$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$REVIEW" "$ZERO_FINDINGS_DIR"
expect_contains 'the review PASS projects the Cleaner' "$TASKS" '**Slice state:** [~] VERIFYING: CLEANER'
```

where `$TEST_ROOT/status-implemented.md` is written once as `printf 'Status: IMPLEMENTED\n'`. `claim`, `expect_failure`, `expect_contains LABEL FILE NEEDLE`, `$TASKS`, `$REPO`, `$FINDING_STATE`, and `$ZERO_FINDINGS_DIR` already exist in this file. Delete the `verifying-security` step (line 99-101). Change the `verifying-hardener` call to pass the Architect report. The ACCEPT count assertion (line 108) stays `8`.

3. In the qa-grouped-findings test (line 119-151) replace the `verifying-security` step with the `reviewing` and `verifying-cleaner` steps above.

4. Replace the repair test (line 153-209) with:

```bash
make_fixture review-round
claim slice-1-implementer implementer
"$SLICE_STATE" "$PLAN" 1 implementing
"$SLICE_STATE" "$PLAN" 1 reviewing "$IMPLEMENTER"
claim slice-1-review task-reviewer
expect_failure 'an open Important review finding cannot enter the Cleaner' \
  "$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$REVIEW_FAIL" "$REVIEW_FINDINGS"
"$FINDING_STATE" "$PLAN" report 1 'Task Reviewer' "$REVIEW_FAIL" "$REVIEW_FINDINGS" >/dev/null
expect_contains 'REVIEWING is projected' "$TASKS" '**Slice state:** [~] REVIEWING'
claim finding-GDD-F0001-dispose controller
cat >"$TEST_ROOT/repairing.md" <<EOF
Disposition: REPAIRING
Repair hypothesis: return the error
Repair base: $(git -C "$REPO" rev-parse HEAD)
Replay through: re-review
EOF
"$FINDING_STATE" "$PLAN" transition GDD-F0001 REPAIRING "$TEST_ROOT/repairing.md"
claim finding-GDD-F0001-repair-start-1 controller
printf 'Repair round: 1\nExecutor: fixer-max\nAgent ID: fixer-1\nRepair hypothesis: return the error\n' >"$TEST_ROOT/start.md"
"$FINDING_STATE" "$PLAN" repair-start GDD-F0001 "$TEST_ROOT/start.md"
claim finding-GDD-F0001-repair-result-1 fixer-max
"$FINDING_STATE" "$PLAN" repair-result GDD-F0001 "$FIXER_REPORT"
claim slice-1-review re-reviewer
"$FINDING_STATE" "$PLAN" report 1 Re-reviewer "$REVIEW" "$ZERO_FINDINGS_DIR"
claim finding-GDD-F0001-repair-finish-1 controller
cat >"$TEST_ROOT/finish.md" <<EOF
Repair round: 1
Executor: fixer-max
Agent ID: fixer-1
Repair head: $(git -C "$REPO" rev-parse HEAD)
Replay status: VERIFIED
Replay evidence: $REVIEW
EOF
"$FINDING_STATE" "$PLAN" repair-finish GDD-F0001 "$TEST_ROOT/finish.md"
claim finding-GDD-F0001-resolve controller
printf 'Disposition: RESOLVED\nResolution evidence: %s\n' "$TEST_ROOT/finish.md" >"$TEST_ROOT/resolved.md"
"$FINDING_STATE" "$PLAN" transition GDD-F0001 RESOLVED "$TEST_ROOT/resolved.md"
claim slice-1-review re-reviewer
"$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$REVIEW" "$ZERO_FINDINGS_DIR"
expect_contains 'the review PASS projects the Cleaner' "$TASKS" '**Slice state:** [~] VERIFYING: CLEANER'
```

`$TEST_ROOT` is the fixture directory the existing test already creates.

- [ ] **Step 2: Run the test to see it fail**

Run: `bash /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh`
Expected: FAIL at `reviewing` (`unknown state`).

- [ ] **Step 3: Rewrite `gdd-slice-state`**

Replace the usage block (line 6-28):

```bash
usage() {
  cat >&2 <<'EOF'
usage:
  gdd-slice-state PLAN_FILE SLICE_NUMBER implementing
  gdd-slice-state PLAN_FILE SLICE_NUMBER reviewing IMPLEMENTER_REPORT
  gdd-slice-state PLAN_FILE SLICE_NUMBER verifying-cleaner REVIEW_REPORT FINDINGS_DIR
  gdd-slice-state PLAN_FILE SLICE_NUMBER verifying-architect CLEANER_REPORT FINDINGS_DIR
  gdd-slice-state PLAN_FILE SLICE_NUMBER verifying-hardener ARCHITECT_REPORT FINDINGS_DIR
  gdd-slice-state PLAN_FILE SLICE_NUMBER verifying-qa HARDENER_REPORT FINDINGS_DIR
  gdd-slice-state PLAN_FILE SLICE_NUMBER verified QA_REPORT FINAL_SUITE_REPORT FINDINGS_DIR
EOF
  exit 2
}
```

Delete `feature_repair_affected_slices` (line 41-55).

Replace the case block (line 107-151):

```bash
case "$state" in
  implementing)
    [ $# -eq 3 ] || usage
    target_state='IMPLEMENTING'
    ;;
  reviewing)
    [ $# -eq 4 ] || usage
    require_status_one_of "$4" Implementer DONE DONE_WITH_CONCERNS >/dev/null
    target_state='REVIEWING'
    ;;
  verifying-cleaner)
    [ $# -eq 5 ] || usage
    require_evidence "$4" Review
    target_state='VERIFYING: CLEANER'
    ;;
  verifying-architect)
    [ $# -eq 5 ] || usage
    require_evidence "$4" Cleaner
    target_state='VERIFYING: ARCHITECT'
    ;;
  verifying-hardener)
    [ $# -eq 5 ] || usage
    require_evidence "$4" Architect
    target_state='VERIFYING: HARDENER'
    ;;
  verifying-qa)
    [ $# -eq 5 ] || usage
    require_status "$4" VERIFIED Hardener
    target_state='VERIFYING: QA'
    ;;
  verified)
    [ $# -eq 6 ] || usage
    require_status "$4" VERIFIED QA
    require_status "$5" PASS 'final suite'
    target_state='VERIFIED'
    ;;
  *) usage ;;
esac
```

`require_status FILE STATUS LABEL` and `require_status_one_of FILE LABEL STATUS...` are the existing definitions at line 57-86. `require_status_one_of` prints the matched status, so the call discards it.

Replace the state parse (line 173-184) so the recognised lines are:

```bash
  '**Slice state:** [ ] QUEUED') current_state='QUEUED' ;;
  '**Slice state:** [~] IMPLEMENTING') current_state='IMPLEMENTING' ;;
  '**Slice state:** [~] REVIEWING') current_state='REVIEWING' ;;
  '**Slice state:** [~] VERIFYING: CLEANER') current_state='VERIFYING: CLEANER' ;;
  '**Slice state:** [~] VERIFYING: ARCHITECT') current_state='VERIFYING: ARCHITECT' ;;
  '**Slice state:** [~] VERIFYING: HARDENER') current_state='VERIFYING: HARDENER' ;;
  '**Slice state:** [~] VERIFYING: QA') current_state='VERIFYING: QA' ;;
  '**Slice state:** [x] VERIFIED') current_state='VERIFIED' ;;
```

Delete the `repair-entry` call (line 186-194) and the verifying-cleaner active-claim block (line 196-214).

Replace the transitions (line 225-242):

```bash
case "$current_state -> $target_state" in
  'QUEUED -> IMPLEMENTING'|\
  'IMPLEMENTING -> REVIEWING'|\
  'REVIEWING -> VERIFYING: CLEANER'|\
  'VERIFYING: CLEANER -> VERIFYING: ARCHITECT'|\
  'VERIFYING: ARCHITECT -> VERIFYING: HARDENER'|\
  'VERIFYING: HARDENER -> VERIFYING: QA'|\
  'VERIFYING: QA -> VERIFIED') ;;
  *) fail "slice $slice cannot move from $current_state to $target_state" ;;
esac
```

Keep the exact `fail` message wording the file uses today for an illegal transition.

Replace the accept case (line 244-281):

```bash
active_claim=$("$workflow_state" "$plan" status | sed -n 's/^Active claim: //p')
case "$state" in
  implementing)
    [ "$active_claim" = "slice-$slice-implementer" ] \
      || fail "implementing requires the active claim slice-$slice-implementer"
    "$workflow_state" "$plan" project >/dev/null
    ;;
  reviewing)
    [ "$active_claim" = "slice-$slice-implementer" ] \
      || fail "reviewing requires the active claim slice-$slice-implementer"
    "$workflow_state" "$plan" accept-active "$active_claim" PASS "$4" >/dev/null
    ;;
  verifying-cleaner)
    review_status=$(awk -F '\t' -v obligation="slice-$slice-review" '$1 == obligation { print $2; exit }' "$status_file")
    if [ "$active_claim" = "slice-$slice-review" ]; then
      for finding_file in "$5"/*.md; do
        [ -f "$finding_file" ] || continue
        case "$(sed -n 's/^Severity claim: //p' "$finding_file" | sed -n 1p)" in
          Critical|Important) fail "verifying-cleaner requires no open Critical or Important review finding: $finding_file" ;;
        esac
      done
      open_review_finding=$(awk -F '\t' -v scope="$slice" '
        $2 == scope && ($3 == "Task Reviewer" || $3 == "Re-reviewer") \
          && ($4 == "REPORTED" || $4 == "REPAIRING" || $4 == "RESOLVED" || $4 == "DEFERRED" || $4 == "DISMISSED" || $4 == "PARKED" || $4 == "BLOCKED") { state[$1] = $4 }
        END { for (id in state) if (state[id] == "REPORTED" || state[id] == "REPAIRING") { print id; exit } }
      ' "$workspace/findings.tsv")
      [ -z "$open_review_finding" ] \
        || fail "verifying-cleaner requires no open Critical or Important review finding: $open_review_finding"
      GDD_FINDINGS_DIR="$5" "$workflow_state" "$plan" accept-active "$active_claim" PASS "$4" >/dev/null
    elif [ "$review_status" = COMPLETE ]; then
      "$workflow_state" "$plan" project >/dev/null
    else
      fail "verifying-cleaner requires the active claim slice-$slice-review or an accepted review"
    fi
    ;;
  verifying-architect)
    [ "$active_claim" = "slice-$slice-cleaner" ] || fail "verifying-architect requires the active claim slice-$slice-cleaner"
    GDD_FINDINGS_DIR="$5" "$workflow_state" "$plan" accept-active "$active_claim" PASS "$4" >/dev/null
    ;;
  verifying-hardener)
    [ "$active_claim" = "slice-$slice-architect" ] || fail "verifying-hardener requires the active claim slice-$slice-architect"
    GDD_FINDINGS_DIR="$5" "$workflow_state" "$plan" accept-active "$active_claim" PASS "$4" >/dev/null
    ;;
  verifying-qa)
    [ "$active_claim" = "slice-$slice-hardener" ] || fail "verifying-qa requires the active claim slice-$slice-hardener"
    GDD_FINDINGS_DIR="$5" "$workflow_state" "$plan" accept-active "$active_claim" PASS "$4" >/dev/null
    ;;
  verified)
    [ "$active_claim" = "slice-$slice-qa" ] || fail "verified requires the active claim slice-$slice-qa"
    GDD_FINDINGS_DIR="$6" "$workflow_state" "$plan" accept-active "$active_claim" SliceVerifiedMacro "$4" "$5" >/dev/null
    ;;
esac
```

Keep how the existing file already handles `implementing` and `verified` (result kinds, argument positions, project call) if it differs from the sketch above. Only the `reviewing` and `verifying-cleaner` branches are new logic. The `verifying-cleaner` ledger scan is the second half of D2: a Task Reviewer or Re-reviewer finding for this slice whose latest lifecycle state is `REPORTED` or `REPAIRING` blocks the PASS even when the new findings directory is empty (the window between `repair-result` and `repair-finish`). The ledger columns are id, scope, origin, state, one row per transition, so the awk keeps the last lifecycle row per id. Define `status_file` once before the case: `workspace=$("$script_dir/gdd-workspace" "$plan")` and `status_file="$workspace/workflow-v1/projections/status.tsv"`. The `status` call at the top of the script refreshes that file.

Delete the `required_origin` check (line 283-288) and every remaining reference to `required_origin`, `Fixer`, or `SECURITY`.

- [ ] **Step 4: Verify nothing references the removed states**

Run:

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts && grep -n 'security\|SECURITY\|repairing\|REPAIRING\|repair-entry\|required_origin\|Fixer\|affected' gdd-slice-state gdd-slice-state.test.sh
```

Expected: no output.

- [ ] **Step 5: Run every engine test**

Run:

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts && bash gdd-workflow-state.test.sh && bash gdd-finding-state.test.sh && bash gdd-slice-state.test.sh
```

Expected: all three PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership && git add skills/gauntlet-driven-development/scripts/gdd-slice-state skills/gauntlet-driven-development/scripts/gdd-slice-state.test.sh && git commit -m "feat(gdd): project the review stage in slice state"
```

### Task 5: Policy version 2 and readiness

**Files:**
- Modify: `skills/gauntlet-driven-development/finding-policy.md` (whole body)
- Modify: `skills/gauntlet-driven-development/scripts/gdd-readiness:18` and `:141`
- Test: `tests/openspec-gdd/test-gdd-readiness.sh:184`, `:233-238`, `:251`

**Interfaces:**
- Consumes: `gdd-workflow-state PLAN format-version` printing `2` (Task 1).
- Produces: `Policy-Version: 2`. The readiness check still requires the nine headings in `policy_headings`.

- [ ] **Step 1: Update the readiness test**

In `tests/openspec-gdd/test-gdd-readiness.sh`:

1. Line 184: the skill fixture writes `Policy-Version: 2`.
2. Line 233: the unsupported-engine fixture prints `1` instead of `2`.
3. Line 238: expect `FAIL: GDD workflow state engine reports unsupported format version: 1`.
4. Line 251: expect `FAIL: GDD finding policy must contain exactly one Policy-Version: 2`.

- [ ] **Step 2: Run the readiness test to see it fail**

Run: `bash /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/tests/openspec-gdd/test-gdd-readiness.sh`
Expected: FAIL. The real policy still says `Policy-Version: 1` and the readiness script still expects `1`.

- [ ] **Step 3: Update `gdd-readiness`**

Line 18: `EXPECTED_POLICY_VERSION='Policy-Version: 2'`.
Line 141: `if [[ "$format_version" != 2 ]]; then`.

- [ ] **Step 4: Replace `finding-policy.md`**

Write the file with this exact content:

````markdown
# GDD finding policy

Policy-Version: 2

## Authority

Lifecycle roles report technical findings and verification verdicts. The GDD
controller verifies each finding and chooses its workflow disposition. The
advisor decides the consultation cases listed under Fable. The approved
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

## Fable

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
`PARK`, `ESCALATE`, or `USER:<ruling>`. `Fable result:` on a terminal
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
````

- [ ] **Step 5: Run the readiness test**

Run: `bash /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/tests/openspec-gdd/test-gdd-readiness.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership && git add skills/gauntlet-driven-development/finding-policy.md skills/gauntlet-driven-development/scripts/gdd-readiness tests/openspec-gdd/test-gdd-readiness.sh && git commit -m "feat(gdd): publish finding policy version 2"
```

### Task 6: Skill body for the review ceremony

**Files:**
- Modify: `skills/gauntlet-driven-development/SKILL.md` (slice ceremony 62-81, findings section 89-127, completion record 128-135, per-finding record 149-163, ruling list 176-188, repair record 202-280, feature closing 282-353, rationalizations 363-370, red flags 377-380)

**Interfaces:**
- Consumes: every command name from Tasks 3 and 4 (`report`, `transition`, `consult`, `repair-start`, `repair-result`, `repair-finish`, `guard`, `digest`, `reviewing`, `verifying-cleaner`).
- Produces: prose only. No script reads the skill body. The readiness check reads `finding-policy.md`, not this file.

Edit by anchor text, not by line number, because each edit shifts later lines. Work top to bottom. Every replacement below is the complete new text for the anchored span.

- [ ] **Step 1: Slice ceremony**

Replace the list items numbered 3, 4, and 5 under `## Slice ceremony` (the items starting `3. Verify the report`, `4. Run one agent at a time`, `5. Every lifecycle role receives`) with:

```markdown
3. Verify the report and non-empty commit range. Do not accept self-reported completion. Mark each proven coarse implementation task `[x]`, then run `scripts/gdd-slice-state PLAN_FILE N reviewing IMPLEMENTER_REPORT`. The report must carry `Status: DONE` or `Status: DONE_WITH_CONCERNS`.
4. Dispatch the Task Reviewer with the stock `skills/subagent-driven-development/task-reviewer-prompt.md` template, unchanged, plus the `[gdd-finding-report]` addendum. Give it the brief, the global constraints, the Implementer report path, and the package from `scripts/review-package PLAN_FILE BASE HEAD` for the slice range. Choose its model per the Subagent-Driven Development Model Selection section, never below the Implementer's tier. It writes `Finding count: N` and one finding file per Critical, Important, or Minor issue with `Origin role: Task Reviewer`. A ❌ spec-compliance item is Important unless the reviewer marks it Critical. Check each ⚠️ item against the cited code and record the result in the review acceptance. Accept the review with `scripts/gdd-finding-state PLAN_FILE report N 'Task Reviewer' REVIEW_REPORT FINDINGS_DIR`. It records PASS when no Critical or Important finding is open and FAIL otherwise. FAIL starts the slice fix rounds below. After PASS, run `scripts/gdd-slice-state PLAN_FILE N verifying-cleaner REVIEW_REPORT FINDINGS_DIR`.
5. Run one agent at a time in this exact order: `cleaner -> architect -> hardener -> e2e-runner [gdd-gate: slice-qa]`. Before each dispatch after Cleaner, advance the state with the prior role's evidence and that role's `FINDINGS_DIR`: `verifying-architect`, `verifying-hardener`, then `verifying-qa`. Pass the QA `FINDINGS_DIR` with its final-suite evidence to `verified` so QA, its findings, the final suite, and verification remain one transaction. Each worker fixes inside its remit in place and reports anything outside it under `## Observations` as findings with its own `Origin role`. A worker observation goes to the advisor under case C1 before the next worker is dispatched.
6. Every lifecycle role receives the slice brief, exact behavior and QA references, current revision, prior verdict or commit, report path, applicable commands, and this exact addendum. Do not add it to Fixer Max, which receives only findings already in `REPAIRING`.
```

Renumber the following item `6. After QA reports` to `7.`.

Replace the sentence `This contract applies to Cleaner, Architect, Security Reviewer, Hardener, QA,\nand Branch Reviewer.` with `This contract applies to the Task Reviewer, Re-reviewer, Cleaner, Architect,\nHardener, QA, Branch Reviewer, and Security Reviewer.`

- [ ] **Step 2: Findings section**

Replace the heading `## Findings and replay` and its first paragraph (`A first full-slice pass and a repair replay have different scopes. A repair replay never expands to the whole slice.`) with:

```markdown
## Findings and fix rounds

A slice has one review, bounded fix rounds, and one first pass per worker. Nothing is replayed.
```

In item 3 of the controller list, replace `Use the current slice number for slice roles and `feature` for Branch Reviewer.` with `Use the current slice number for slice roles and `feature` for Branch Reviewer and Security Reviewer.`

Replace the paragraph beginning `Before `DEFERRED`, `DISMISSED`, `PARKED`, `BLOCKED`, or a scope-expanding\nrepair, invoke `fable-advisor:advise`` through `decisions remain authoritative.` with:

```markdown
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
```

- [ ] **Step 3: Completion and per-finding records**

Under `### Completion record`, after the sentence ending `while the controller chooses the disposition.`, add:

```markdown
Repeat every consultation as
`Advisor consultation <K>: <finding IDs>; <case>; <decision>; <reason>; cost if wrong: <cost>`.
```

After the per-finding execution record code block, replace the sentence `Otherwise use `Fable gate: NOT REQUIRED:` and name the verified\nconditions that excluded every gate. `UNAVAILABLE` is valid only after an actual `fable-advisor:advise` invocation fails.` with:

```markdown
Otherwise use `Fable gate: NOT REQUIRED:` and name the verified
conditions that excluded every gate. `Fable result:` points to the
consultation record file. `UNAVAILABLE` is valid only after the built-in
`advisor` tool errors on Claude Code, or the `$fable-advisor:advise` skill
returns `Fable Advisor failed: <exact failure>. No advisory ruling was
produced.` on Codex. A `REPAIRING` disposition names `Replay through:
re-review` or `Replay through: downstream`. There is no `Affected slices`
field.
```

Add this subsection directly before the paragraph `The mandatory-gates field is literal`:

````markdown
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
````

In numbered item 1 of the ruling list, replace `or `feature-findings-digest` for a Branch\n   Reviewer finding.` with `or `feature-findings-digest` for a Branch\n   Reviewer or Security Reviewer finding.` Replace item 2 (`Use the ordered slice-repair execution record below for ordinary repairs.\n   Final-wave repairs use the stricter order below.`) with:

```markdown
2. Use the slice fix round record below for slice findings and the feature
   closing dispatch order for feature findings.
```

- [ ] **Step 4: Replace the repair record and replay text**

Replace everything from the heading `### Ordered slice-repair execution record` through the line `Keep bounded escalation and ledger entries from the approved plan.` with:

```markdown
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
(`Executor: fixer-max`, or `Executor: hardener` for the Hardener's own
production fix), the dispatch, `repair-result`, the next worker of the slice
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
```

- [ ] **Step 5: Replace feature closing**

Replace everything from the heading `## Feature closing` through the sentence `There is no second final fix wave.` (the words `Claim the digest obligation` start the text that stays) with:

```markdown
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

```

In the digest paragraph that now follows, replace `condition, and evidence digest.` with `condition, and evidence digest, plus every consultation under\n`## Advisor consultations`.` Keep the digest and complete commands exactly as written.

Delete the final paragraph of the section (`The fresh post-wave Branch Reviewer brief includes the full branch review\npackage, ... even when that finding\nlater resolves.`).

- [ ] **Step 6: Rationalizations and red flags**

In the `## Rationalizations` table delete the rows starting `| "Fresh Security means reviewing the whole slice again."` and `| "Focused tests pass after the authorization fix."`. Replace the row starting `| "The Architect approved before the fix."` with:

```markdown
| "The Architect approved before the fix."                 | A fix after a worker's PASS is a downstream finding. The next worker verifies it. A prior verdict is not coverage. |
```

Replace the row starting `| "QA already passed."` with:

```markdown
| "QA already passed."                                     | A production fix after QA requires one fresh full-slice QA pass.                                    |
```

Add these rows at the end of the table:

```markdown
| "One more replay will fix it."                           | There is no replay. An open finding takes a numbered fix round with a fresh fixer-max, capped at 5. |
| "The worker can fix it while it is there."               | A worker fixes only inside its remit. Everything else is an observation the advisor routes.        |
| "The advisor said fix it, no record needed."             | Every consultation is recorded with `consult` before the controller acts on it.                    |
```

Replace the last three bullets of `## Red flags` (`Giving a replayed role the whole slice`, `Replaying a role after the repair's originating gate`, `Omitting a required delta replay role`) with:

```markdown
- Giving the Re-reviewer the whole slice instead of the fix range.
- Dispatching a fixer-max without `repair-start`, or acting on an advisor ruling without a consultation record.
- Starting round 6, or a second feature closing fix dispatch.
```

- [ ] **Step 7: Verify the skill text**

Run:

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development && grep -n 'security-reviewer\|verifying-security\|Fixer or Fixer Max\|Round 1 uses\|Final-wave\|final-wave\|Affected slices\|repairing FINDING\|repair-entry\|fixer-delta\|exact-delta\|Delta-scoped' SKILL.md
```

Expected: no output.

Run:

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development && grep -n -i 'replay' SKILL.md
```

Expected: only lines containing `Replay through`, `Replay status`, `Replay evidence`, `Nothing is replayed`, `There is no replay`, or `no slice replay`.

Run:

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development && grep -rn 'verifying-security\|slice-N-security\|repair-entry\|Final-wave' --include='*.md' . | grep -v '^./SKILL.md'
```

Expected: no output. If a file under this skill directory other than `SKILL.md` and `finding-policy.md` still names the old ceremony, do not edit it. Report the paths in the task summary.

- [ ] **Step 8: Run the readiness test and commit**

Run: `bash /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/tests/openspec-gdd/test-gdd-readiness.sh`
Expected: PASS.

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership && git add skills/gauntlet-driven-development/SKILL.md && git commit -m "docs(gdd): describe the review stage and fix rounds"
```

### Task 7: Security Reviewer as the whole-branch closing reviewer

Working directory: `/Users/bmurgic/.claude`, branch `main`. This repo has about 145 unrelated dirty files. Stage only the named files.

**Files:**
- Modify: `agents/security-reviewer.md` (frontmatter 1-9, `## Slice Review Mode` 20, dispatch inputs 24, scope sentence 25, digest sentence 37)
- Modify: `hooks/guard-dispatch-model.sh:12` and the `security-reviewer)` case at 65-70
- Modify: `codex-agents/security-reviewer.toml` (description line 2, `model_reasoning_effort` line 4, SHA line 8, adaptation bullet line 17, body)
- Test: `superpowers-bridge/scripts/agent-source-parity.test.sh:84-87`

**Interfaces:**
- Consumes: nothing from Tasks 1 to 6. The agent text is prose. The regeneration script below reads the agent body.
- Produces: `agents/security-reviewer.md` with `model: fable`, `effort: high`. `codex-agents/security-reviewer.toml` with `model_reasoning_effort = "xhigh"`. The hook denies any `security-reviewer` dispatch whose model override does not contain `fable`.

- [ ] **Step 1: Tighten the parity test**

In `superpowers-bridge/scripts/agent-source-parity.test.sh` replace lines 84-87 with:

```python
security = tomllib.loads((root / "codex-agents" / "security-reviewer.toml").read_text())
assert security["model"] == "gpt-5.6-sol"
assert security["model_reasoning_effort"] == "xhigh"
print("PASS  Codex Security Reviewer uses gpt-5.6-sol at xhigh reasoning")
```

- [ ] **Step 2: Run the parity test to see it fail**

Run: `bash /Users/bmurgic/.claude/superpowers-bridge/scripts/agent-source-parity.test.sh`
Expected: FAIL at the `security["model_reasoning_effort"] == "xhigh"` assertion.

- [ ] **Step 3: Rewrite the agent frontmatter and review mode**

Replace lines 1-9 of `agents/security-reviewer.md` with:

```markdown
---
name: security-reviewer
description: Read-only whole-branch security reviewer. Dispatched once at feature closing after every slice of an OpenSpec change or Superpowers plan is verified, and once more as a scoped re-review after the closing fix dispatch. Flags secrets, SSRF, injection, unsafe crypto, authorization failures, and OWASP Top 10 vulnerabilities. Reports findings; fixer-max applies them.
tools: ["Read", "Bash", "Grep", "Glob", "Skill"]
# Security review pin - fable at high effort (the whole-branch review rung).
# guard-dispatch-model.sh rejects overrides.
model: fable
effort: high
---
```

Replace line 20 `## Slice Review Mode` with `## Branch Review Mode`.

Replace line 24 with:

```markdown
The dispatch must identify the plan base ref, the repository or worktree path, the spec sources (the OpenSpec change directory or the Superpowers plan file), the whole-branch review package or the base to HEAD range to generate it from, the project's check command, every deferred, dismissed, and parked finding with its ruling, cost if wrong, and wake condition, every advisor consultation record, and a unique verdict-file path. A scoped re-review dispatch instead names the fix range from `scripts/review-package`, the Security Reviewer findings to verdict, and the verdict-file path. If any input is missing, return `Status: NEEDS_CONTEXT` and name it.
```

Replace line 25 with:

```markdown
Review the whole branch diff through your security lenses. In a scoped re-review, verdict each listed finding `ADDRESSED` or `NOT ADDRESSED`, inspect the fix diff for new breakage, and do not re-review untouched code. Cleaner, Architect, Hardener, QA, and the Branch Reviewer own their separate concerns; do not re-flag issues that are only style or maintainability.
```

In line 37 replace the two sentences `Only `Status: CLEAN` hands the slice to the Hardener. Findings route to a fixer, then scoped Cleaner and Architect reruns, followed by a fresh Security Reviewer.` with:

```markdown
Findings are recorded with scope `feature` and join the closing fix dispatch. A fresh Security Reviewer re-reviews the fix range.
```

Then check the rest of the body for the words `slice diff`, `the slice`, `Architect-approved commit`, and `Hardener` used as the next stage:

```bash
grep -n 'slice\|Hardener' /Users/bmurgic/.claude/agents/security-reviewer.md
```

Rewrite each remaining hit so it names the branch diff or the closing fix dispatch. The review method (authorization obligations first, per-handler AUTHZ CHECK, lens scan, test discrimination, backward trace) stays unchanged in content and runs over the whole branch diff.

- [ ] **Step 4: Update the dispatch hook**

In `hooks/guard-dispatch-model.sh` replace line 12 with:

```bash
# 6b) security-reviewer pins fable (frontmatter) - a non-fable model override is rejected.
```

In the `security-reviewer)` case (line 65-70) replace `*opus*) ;;` with `*fable*) ;;` and the deny line with:

```bash
        *) deny "security-reviewer runs on fable only (model override '$model' rejected). Omit the model param - the agent definition pins fable." ;;
```

Verify the hook:

```bash
printf '%s' '{"tool_input":{"subagent_type":"security-reviewer","model":"opus"}}' | sh /Users/bmurgic/.claude/hooks/guard-dispatch-model.sh; echo "exit=$?"
```

Expected: the deny message naming fable and a non-zero exit (the same exit code the other deny branches use).

```bash
printf '%s' '{"tool_input":{"subagent_type":"security-reviewer","model":"fable"}}' | sh /Users/bmurgic/.claude/hooks/guard-dispatch-model.sh; echo "exit=$?"
```

Expected: no deny output, `exit=0`.

- [ ] **Step 5: Regenerate the Codex TOML**

Edit the header of `codex-agents/security-reviewer.toml`:

```bash
cd /Users/bmurgic/.claude && sed -i '' \
  -e '2s|.*|description = "Read-only whole-branch security reviewer. Dispatched once at feature closing after every slice of an OpenSpec change or Superpowers plan is verified, and once more as a scoped re-review after the closing fix dispatch."|' \
  -e '4s|.*|model_reasoning_effort = "xhigh"|' \
  -e 's|^- Do not delegate. Review only the dispatched slice and return the required digest to the parent agent.$|- Do not delegate. Review only the dispatched branch diff and return the required digest to the parent agent.|' \
  codex-agents/security-reviewer.toml
```

Then regenerate the body and SHA:

```bash
python3 - "$HOME/.claude" security-reviewer <<'PY'
import hashlib, pathlib, re, sys
root = pathlib.Path(sys.argv[1]); role = sys.argv[2]
source = (root / "agents" / f"{role}.md").read_text()
body = re.fullmatch(r"---\n.*?\n---\n\n(.*)", source, re.DOTALL).group(1)
toml_path = root / "codex-agents" / f"{role}.toml"
toml = toml_path.read_text()
marker = f"<!-- SOURCE_BODY_BEGIN: /Users/bmurgic/.claude/agents/{role}.md -->\n\n"
head = toml.split(marker, 1)[0]
head = re.sub(r"^# Source body SHA-256: [0-9a-f]{64}$", "# Source body SHA-256: " + hashlib.sha256(body.encode()).hexdigest(), head, flags=re.MULTILINE)
toml_path.write_text(head + marker + body + "'''\n")
PY
```

Confirm the file still ends with the closing `'''` line:

```bash
tail -c 5 /Users/bmurgic/.claude/codex-agents/security-reviewer.toml | od -c
```

Expected: `\n ' ' ' \n`.

- [ ] **Step 6: Run the parity and install tests**

Run: `bash /Users/bmurgic/.claude/superpowers-bridge/scripts/agent-source-parity.test.sh`
Expected: PASS, including `PASS  Codex Security Reviewer uses gpt-5.6-sol at xhigh reasoning`.

Run: `bash /Users/bmurgic/.claude/scripts/install-codex-agents.test.sh`
Expected: PASS. This test copies the TOMLs through the bootstrap and compares them byte for byte.

- [ ] **Step 7: Commit only the named files**

```bash
cd /Users/bmurgic/.claude && git add agents/security-reviewer.md hooks/guard-dispatch-model.sh codex-agents/security-reviewer.toml superpowers-bridge/scripts/agent-source-parity.test.sh && git commit -m "feat(workflow): move security review to feature closing on fable"
```

Confirm with `git -C /Users/bmurgic/.claude show --stat HEAD` that exactly four files are in the commit.

### Task 8: Branch Reviewer, Architect, and QA bodies

Working directory: `/Users/bmurgic/.claude`, branch `main`. Stage only the named files.

**Files:**
- Modify: `agents/branch-reviewer.md` (description 7, opening paragraph 18, inputs 22-31, method 33-43)
- Modify: `agents/architect.md:22`, `:28`, `:85`
- Modify: `agents/e2e-runner.md:28`, `:78`, `:80`
- Modify: `codex-agents/branch-reviewer.toml` (description 2, SHA 8, body), `codex-agents/architect.toml` (SHA 8, body), `codex-agents/e2e-runner.toml` (SHA 8, body)
- Test: `superpowers-bridge/scripts/agent-source-parity.test.sh:57-60`

**Interfaces:**
- Consumes: the regeneration script from Task 7 step 5, run once per role.
- Produces: the architect handoff sentence `Return the short handoff digest to the orchestrator, which dispatches the Hardener.` that the parity test asserts.

- [ ] **Step 1: Tighten the parity test**

Replace lines 57-60 of `superpowers-bridge/scripts/agent-source-parity.test.sh` with:

```python
    if role == "architect":
        required_handoff = "Return the short handoff digest to the orchestrator, which dispatches the Hardener."
        if required_handoff not in claude_body:
            raise AssertionError("architect: next handoff must target Hardener")
```

- [ ] **Step 2: Run the parity test to see it fail**

Run: `bash /Users/bmurgic/.claude/superpowers-bridge/scripts/agent-source-parity.test.sh`
Expected: FAIL with `architect: next handoff must target Hardener`.

- [ ] **Step 3: Edit the Architect**

In `agents/architect.md`:

- Line 22: replace `which dispatches the Security Reviewer.` with `which dispatches the Hardener.`
- Line 28: replace `before handing the current slice to the Security Reviewer.` with `before handing the current slice to the Hardener.`
- Line 85: replace `return the handoff digest for the Security Reviewer.` with `return the handoff digest for the Hardener.`

Verify: `grep -n 'Security Reviewer' /Users/bmurgic/.claude/agents/architect.md` prints nothing.

- [ ] **Step 4: Edit the Branch Reviewer**

In `agents/branch-reviewer.md`:

- Line 7: replace `cross-slice integration, whole-feature quality, and emergent security risks. Returns severity-tagged` with `cross-slice integration, and whole-feature quality. Returns severity-tagged`.
- Line 18: replace `accumulated drift, and security risks created by the slices in combination.` with `and accumulated drift.`
- Under `## Inputs the dispatch prompt gives you`, replace item 5 (`5. Optionally: findings already fixed in prior slice reviews (do not re-report them), and known pre-existing failures.`) with:

```markdown
5. Every `DEFERRED`, `DISMISSED`, and `PARKED` finding with its Finding ID, ruling, cost if wrong, and wake condition, and every advisor consultation record. Do not re-report a finding the controller already ruled on; cite its Finding ID if the branch changes its premise.
6. Optionally: known pre-existing failures.

A scoped re-review dispatch instead gives the fix range from `scripts/review-package`, the Branch Reviewer findings to verdict, and the verdict-file path. In that mode, verdict each listed finding `ADDRESSED` or `NOT ADDRESSED`, inspect the fix diff for new breakage, and do not re-review untouched code.
```

- Under `## Method (in order)`, delete step 7 (`7. **Emergent security pass:** ...`). Renumber `8.` to `7.` and `9.` to `8.`. After the renumbered list add one line:

```markdown
Security review belongs to the Security Reviewer, which runs on the same branch package. Do not report or suggest security findings.
```

Verify: `grep -n -i 'security' /Users/bmurgic/.claude/agents/branch-reviewer.md` prints only the new sentence.

- [ ] **Step 5: Edit the QA runner**

In `agents/e2e-runner.md`:

- Line 28: replace `implementation base and current Hardener commit,` with `implementation base and current Hardener commit, the recorded fix commits (short SHA and Finding ID) made after the Hardener's verified commit,`.
- Line 78: replace the whole bullet with:

```markdown
- If the application violates an approved scenario or QA observation, return `Status: REPAIR_REQUIRED` with a finding report. Do not repair production code. The orchestrator consults the advisor. A fix is followed by a fresh QA.
```

- Line 80: replace the whole bullet with:

```markdown
- Return `Status: STALE_HARDENER` only when production, acceptance, property-test, architecture-rule, or mutation inputs changed after the Hardener's verified commit with no controller-recorded `fixer-max` or Hardener fix event covering the change. A recorded fix event after the Hardener is verified by QA alone; its mutation evidence is not regenerated. Do not run acceptance QA against an unverified state.
```

Verify: `grep -n 'Security Reviewer\|fixer delta' /Users/bmurgic/.claude/agents/e2e-runner.md` prints nothing.

- [ ] **Step 6: Regenerate the three TOMLs**

Update the Branch Reviewer description:

```bash
cd /Users/bmurgic/.claude && sed -i '' '2s|.*|description = "Read-only whole-branch reviewer after the final verified slice. Reviews whole-spec coverage, cross-slice integration, and accumulated drift."|' codex-agents/branch-reviewer.toml
```

Run the regeneration script from Task 7 step 5 three times, with `branch-reviewer`, `architect`, and `e2e-runner` as the second argument. Then confirm each file ends with `\n'''\n`:

```bash
for r in branch-reviewer architect e2e-runner; do tail -c 5 "/Users/bmurgic/.claude/codex-agents/$r.toml" | od -c | head -1; done
```

- [ ] **Step 7: Run the parity and install tests**

Run: `bash /Users/bmurgic/.claude/superpowers-bridge/scripts/agent-source-parity.test.sh`
Expected: PASS for every role.

Run: `bash /Users/bmurgic/.claude/scripts/install-codex-agents.test.sh`
Expected: PASS.

- [ ] **Step 8: Commit only the named files**

```bash
cd /Users/bmurgic/.claude && git add agents/branch-reviewer.md agents/architect.md agents/e2e-runner.md codex-agents/branch-reviewer.toml codex-agents/architect.toml codex-agents/e2e-runner.toml superpowers-bridge/scripts/agent-source-parity.test.sh && git commit -m "docs(skills): hand the Architect to the Hardener and drop branch security review"
```

Confirm with `git -C /Users/bmurgic/.claude show --stat HEAD` that exactly seven files are in the commit.

### Task 9: Final verification across both repositories

**Files:** none modified.

- [ ] **Step 1: Run every suite**

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/skills/gauntlet-driven-development/scripts && bash gdd-workflow-state.test.sh && bash gdd-finding-state.test.sh && bash gdd-slice-state.test.sh && bash /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership/tests/openspec-gdd/test-gdd-readiness.sh && bash /Users/bmurgic/.claude/superpowers-bridge/scripts/agent-source-parity.test.sh && bash /Users/bmurgic/.claude/scripts/install-codex-agents.test.sh
```

Expected: every suite prints PASS and the chain exits 0.

- [ ] **Step 2: Confirm the old ceremony is gone**

```bash
cd /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership && grep -rn 'slice-[0-9N]*-security\|verifying-security\|repair-entry\|replay-entry\|Final-wave\|Affected slices\|fable-advisor:advise' skills/gauntlet-driven-development tests/openspec-gdd
```

Expected: the only hits are the two `$fable-advisor:advise` mentions in `SKILL.md` (the Codex invocation and the failure text) and the `SKILL.md` sentence `There is no `Affected slices` field.`

```bash
grep -rn 'Security Reviewer' /Users/bmurgic/.claude/agents/architect.md /Users/bmurgic/.claude/agents/e2e-runner.md /Users/bmurgic/.claude/agents/branch-reviewer.md
```

Expected: only the Branch Reviewer sentence that hands security review to the Security Reviewer.

- [ ] **Step 3: Confirm the commit history**

```bash
git -C /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership log --oneline 6264167..HEAD && git -C /Users/bmurgic/.claude log --oneline -2 && git -C /Users/bmurgic/.local/share/bmurgic-superpowers/.claude/worktrees/gdd-security-ownership status --short
```

Expected: seven superpowers commits after the spec commit (this plan, then Tasks 1 to 6), two claude-config commits (Tasks 7 and 8), and no staged or tracked change left in the worktree. `docs/superpowers/wayfinding/` may still show as untracked. Leave it.
