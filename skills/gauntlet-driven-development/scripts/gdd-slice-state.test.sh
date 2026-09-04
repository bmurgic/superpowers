#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SLICE_STATE="$SCRIPT_DIR/gdd-slice-state"
FINDING_STATE="$SCRIPT_DIR/gdd-finding-state"
WORKFLOW_STATE="$SCRIPT_DIR/gdd-workflow-state"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
pass=0
fail=0

record_pass() { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
record_fail() { fail=$((fail + 1)); printf 'FAIL  %s\n' "$1"; }
expect_success() {
  local name=$1
  shift
  if "$@" >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr"; then record_pass "$name"; else record_fail "$name"; sed 's/^/      /' "$TEST_ROOT/stderr"; fi
}
expect_failure() {
  local name=$1
  shift
  if "$@" >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr"; then record_fail "$name"; else record_pass "$name"; fi
}
expect_contains() {
  local name=$1 file=$2 value=$3
  if grep -qF -- "$value" "$file"; then record_pass "$name"; else record_fail "$name"; fi
}
file_sha() { shasum -a 256 "$1" | awk '{ print $1 }'; }

make_fixture() {
  local name=$1
  REPO="$TEST_ROOT/$name/repo"
  CHANGE="$REPO/openspec/changes/$name"
  PLAN="$CHANGE/plan.md"
  TASKS="$CHANGE/tasks.md"
  WORKSPACE="$REPO/.superpowers/gdd/$name"
  mkdir -p "$CHANGE"
  git -C "$REPO" init -q
  git -C "$REPO" config user.name 'Test Bot'
  git -C "$REPO" config user.email test@example.com
  printf '# %s\n' "$name" >"$PLAN"
  printf '%s\n' \
    '## 1. Lifecycle boundary' \
    '**Slice state:** [ ] QUEUED' \
    '' \
    '- [ ] 1.1 Implement the boundary' \
    '- [ ] 1.V **Slice verification gate**' >"$TASKS"
  printf 'fixture\n' >"$REPO/README.md"
  git -C "$REPO" add README.md openspec
  git -C "$REPO" commit -qm 'chore: fixture'
  DISPATCH="$TEST_ROOT/$name-dispatch.md"
  printf 'Dispatch: %s\n' "$name" >"$DISPATCH"
  expect_success "$name initializes v1" "$FINDING_STATE" "$PLAN" init
}

claim() {
  local obligation=$1 actor=$2
  expect_success "claim $obligation" "$WORKFLOW_STATE" "$PLAN" claim "$obligation" "$actor" "$DISPATCH"
}

IMPLEMENTER="$TEST_ROOT/implementer.md"
IMPLEMENTER_CONCERNS="$TEST_ROOT/implementer-concerns.md"
REVIEW="$TEST_ROOT/review.md"
REVIEW_FAIL="$TEST_ROOT/review-fail.md"
CLEANER="$TEST_ROOT/cleaner.md"
ARCHITECT="$TEST_ROOT/architect.md"
HARDENER="$TEST_ROOT/hardener.md"
QA="$TEST_ROOT/qa.md"
SUITE="$TEST_ROOT/suite.md"
FIXER_REPORT="$TEST_ROOT/fixer-report.md"
printf 'Status: DONE\n' >"$IMPLEMENTER"
printf 'Status: DONE_WITH_CONCERNS\n' >"$IMPLEMENTER_CONCERNS"
printf 'Status: PASS\nFinding count: 0\n' >"$REVIEW"
printf 'Status: FAIL\nFinding count: 1\n' >"$REVIEW_FAIL"
printf 'Status: COMPLETE\n' >"$CLEANER"
printf 'Finding count: 0\n' >>"$CLEANER"
printf 'Status: COMPLETE\n' >"$ARCHITECT"
printf 'Finding count: 0\n' >>"$ARCHITECT"
printf 'Status: VERIFIED\n' >"$HARDENER"
printf 'Finding count: 0\n' >>"$HARDENER"
printf 'Status: VERIFIED\n' >"$QA"
printf 'Finding count: 0\n' >>"$QA"
printf 'Status: PASS\n' >"$SUITE"
printf 'Status: FIXED\n' >"$FIXER_REPORT"
ZERO_FINDINGS_DIR="$TEST_ROOT/zero-findings"
mkdir -p "$ZERO_FINDINGS_DIR"
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
printf 'Status: IMPLEMENTED\n' >"$TEST_ROOT/status-implemented.md"

make_fixture authority
before=$(file_sha "$TASKS")
expect_failure 'implementing requires an active receipt' "$SLICE_STATE" "$PLAN" 1 implementing
[ "$before" = "$(file_sha "$TASKS")" ] && record_pass 'unclaimed implementing leaves tasks.md unchanged' || record_fail 'unclaimed implementing leaves tasks.md unchanged'
claim slice-1-implementer implementer
expect_success 'claimed Implementer projects IMPLEMENTING' "$SLICE_STATE" "$PLAN" 1 implementing
expect_contains 'IMPLEMENTING is projected' "$TASKS" '**Slice state:** [~] IMPLEMENTING'
expect_failure 'reviewing requires a DONE implementer report' \
  "$SLICE_STATE" "$PLAN" 1 reviewing "$TEST_ROOT/status-implemented.md"
expect_success 'Implementer acceptance projects REVIEWING' "$SLICE_STATE" "$PLAN" 1 reviewing "$IMPLEMENTER"
expect_contains 'REVIEWING is projected' "$TASKS" '**Slice state:** [~] REVIEWING'
expect_failure 'verifying-cleaner without a review claim fails' \
  "$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$REVIEW" "$ZERO_FINDINGS_DIR"
claim slice-1-review task-reviewer
expect_success 'review PASS projects Cleaner' "$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$REVIEW" "$ZERO_FINDINGS_DIR"
expect_contains 'the review PASS projects the Cleaner' "$TASKS" '**Slice state:** [~] VERIFYING: CLEANER'
expect_failure 'Cleaner transition without a Cleaner receipt fails' "$SLICE_STATE" "$PLAN" 1 verifying-architect "$CLEANER" "$ZERO_FINDINGS_DIR"
claim slice-1-cleaner cleaner
expect_failure 'Cleaner cannot advance without grouped finding evidence' "$SLICE_STATE" "$PLAN" 1 verifying-architect "$CLEANER"
expect_success 'Cleaner acceptance projects Architect' "$SLICE_STATE" "$PLAN" 1 verifying-architect "$CLEANER" "$ZERO_FINDINGS_DIR"
claim slice-1-architect architect
expect_success 'Architect acceptance projects Hardener' "$SLICE_STATE" "$PLAN" 1 verifying-hardener "$ARCHITECT" "$ZERO_FINDINGS_DIR"
claim slice-1-hardener hardener
expect_success 'Hardener acceptance projects QA' "$SLICE_STATE" "$PLAN" 1 verifying-qa "$HARDENER" "$ZERO_FINDINGS_DIR"
claim slice-1-qa qa
expect_success 'QA macro verifies the slice atomically' "$SLICE_STATE" "$PLAN" 1 verified "$QA" "$SUITE" "$ZERO_FINDINGS_DIR"
expect_contains 'VERIFIED is projected' "$TASKS" '**Slice state:** [x] VERIFIED'
expect_contains 'verification gate is projected closed' "$TASKS" '- [x] 1.V **Slice verification gate**'
[ "$(awk -F '\t' '$5 == "ACCEPT" { count++ } END { print count + 0 }' "$WORKSPACE/workflow-v1/events.tsv")" -eq 8 ] \
  && record_pass 'QA macro publishes QA, final-suite, and verified events' \
  || record_fail 'QA macro publishes QA, final-suite, and verified events'

sed -i.bak 's/\*\*Slice state:\*\* \[x\] VERIFIED/**Slice state:** [ ] QUEUED/' "$TASKS"
rm "$TASKS.bak"
expect_success 'status rebuilds a mutated projection' "$WORKFLOW_STATE" "$PLAN" status
expect_contains 'reducer restores VERIFIED after manual mutation' "$TASKS" '**Slice state:** [x] VERIFIED'

make_fixture implementer-concerns
claim slice-1-implementer implementer
"$SLICE_STATE" "$PLAN" 1 implementing >/dev/null
expect_success 'reviewing accepts DONE_WITH_CONCERNS' "$SLICE_STATE" "$PLAN" 1 reviewing "$IMPLEMENTER_CONCERNS"
expect_contains 'DONE_WITH_CONCERNS projects REVIEWING' "$TASKS" '**Slice state:** [~] REVIEWING'
claim slice-1-review task-reviewer
expect_success 'accepted review projects Cleaner after DONE_WITH_CONCERNS' "$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$REVIEW" "$ZERO_FINDINGS_DIR"
expect_contains 'accepted review projects Cleaner after DONE_WITH_CONCERNS' "$TASKS" '**Slice state:** [~] VERIFYING: CLEANER'

# A QA finding is accepted with QA, the final suite, and verification. The
# macro cannot publish a verified slice without the FindingReported side event.
make_fixture qa-grouped-findings
claim slice-1-implementer implementer
"$SLICE_STATE" "$PLAN" 1 implementing >/dev/null
"$SLICE_STATE" "$PLAN" 1 reviewing "$IMPLEMENTER" >/dev/null
claim slice-1-review task-reviewer
"$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$REVIEW" "$ZERO_FINDINGS_DIR" >/dev/null
claim slice-1-cleaner cleaner
"$SLICE_STATE" "$PLAN" 1 verifying-architect "$CLEANER" "$ZERO_FINDINGS_DIR" >/dev/null
claim slice-1-architect architect
"$SLICE_STATE" "$PLAN" 1 verifying-hardener "$ARCHITECT" "$ZERO_FINDINGS_DIR" >/dev/null
claim slice-1-hardener hardener
"$SLICE_STATE" "$PLAN" 1 verifying-qa "$HARDENER" "$ZERO_FINDINGS_DIR" >/dev/null
claim slice-1-qa qa
QA_FINDINGS_DIR="$TEST_ROOT/qa-findings"
QA_WITH_FINDINGS="$TEST_ROOT/qa-with-findings.md"
mkdir -p "$QA_FINDINGS_DIR"
printf 'Status: VERIFIED\nFinding count: 1\n' >"$QA_WITH_FINDINGS"
printf '%s\n' \
  'Origin role: QA' \
  'Severity claim: Important' \
  'Blocking claim: no' \
  'Observed failure: QA found a verified follow-up.' \
  'Evidence: reports/qa.md' \
  'Violated authority: approved design' \
  'Assumptions: QA evidence is current.' \
  'Failure scenario: verification omits the finding.' \
  'Proposed repair: record the QA finding.' \
  'Repair effects: controller adjudicates the finding.' >"$QA_FINDINGS_DIR/1.md"
expect_success 'QA macro accepts its nonzero grouped finding' "$SLICE_STATE" "$PLAN" 1 verified "$QA_WITH_FINDINGS" "$SUITE" "$QA_FINDINGS_DIR"
expect_contains 'QA grouped finding is projected' "$WORKSPACE/findings.tsv" $'\tQA\tREPORTED\t'
[ "$(awk -F '\t' '$5 == "SIDE" { count++ } END { print count + 0 }' "$WORKSPACE/workflow-v1/events.tsv")" -eq 1 ] \
  && record_pass 'QA macro publishes one FindingReported event' \
  || record_fail 'QA macro publishes one FindingReported event'

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
claim finding-GDD-F0001-repair-result fixer-max
"$FINDING_STATE" "$PLAN" repair-result GDD-F0001 "$FIXER_REPORT"
claim slice-1-review re-reviewer
expect_failure 'a REPAIRING Important review finding blocks Cleaner before repair-finish' \
  "$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$REVIEW" "$ZERO_FINDINGS_DIR"
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

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
