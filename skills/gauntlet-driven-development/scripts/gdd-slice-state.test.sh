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
CLEANER="$TEST_ROOT/cleaner.md"
ARCHITECT="$TEST_ROOT/architect.md"
SECURITY="$TEST_ROOT/security.md"
HARDENER="$TEST_ROOT/hardener.md"
QA="$TEST_ROOT/qa.md"
SUITE="$TEST_ROOT/suite.md"
FIXER="$TEST_ROOT/fixer.md"
printf 'Status: IMPLEMENTED\n' >"$IMPLEMENTER"
printf 'Status: COMPLETE\n' >"$CLEANER"
printf 'Finding count: 0\n' >>"$CLEANER"
printf 'Status: COMPLETE\n' >"$ARCHITECT"
printf 'Finding count: 0\n' >>"$ARCHITECT"
printf 'Status: CLEAN\n' >"$SECURITY"
printf 'Finding count: 0\n' >>"$SECURITY"
printf 'Status: VERIFIED\n' >"$HARDENER"
printf 'Finding count: 0\n' >>"$HARDENER"
printf 'Status: VERIFIED\n' >"$QA"
printf 'Finding count: 0\n' >>"$QA"
printf 'Status: PASS\n' >"$SUITE"
printf 'Status: FIXED\n' >"$FIXER"
ZERO_FINDINGS_DIR="$TEST_ROOT/zero-findings"
mkdir -p "$ZERO_FINDINGS_DIR"

make_fixture authority
before=$(file_sha "$TASKS")
expect_failure 'implementing requires an active receipt' "$SLICE_STATE" "$PLAN" 1 implementing
[ "$before" = "$(file_sha "$TASKS")" ] && record_pass 'unclaimed implementing leaves tasks.md unchanged' || record_fail 'unclaimed implementing leaves tasks.md unchanged'
claim slice-1-implementer implementer
expect_success 'claimed Implementer projects IMPLEMENTING' "$SLICE_STATE" "$PLAN" 1 implementing
expect_contains 'IMPLEMENTING is projected' "$TASKS" '**Slice state:** [~] IMPLEMENTING'
expect_success 'Implementer acceptance projects Cleaner' "$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$IMPLEMENTER"
expect_failure 'Cleaner transition without a Cleaner receipt fails' "$SLICE_STATE" "$PLAN" 1 verifying-architect "$CLEANER" "$ZERO_FINDINGS_DIR"
claim slice-1-cleaner cleaner
expect_failure 'Cleaner cannot advance without grouped finding evidence' "$SLICE_STATE" "$PLAN" 1 verifying-architect "$CLEANER"
expect_success 'Cleaner acceptance projects Architect' "$SLICE_STATE" "$PLAN" 1 verifying-architect "$CLEANER" "$ZERO_FINDINGS_DIR"
claim slice-1-architect architect
expect_success 'Architect acceptance projects Security' "$SLICE_STATE" "$PLAN" 1 verifying-security "$ARCHITECT" "$ZERO_FINDINGS_DIR"
claim slice-1-security security-reviewer
expect_success 'Security acceptance projects Hardener' "$SLICE_STATE" "$PLAN" 1 verifying-hardener "$SECURITY" "$ZERO_FINDINGS_DIR"
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

# A QA finding is accepted with QA, the final suite, and verification. The
# macro cannot publish a verified slice without the FindingReported side event.
make_fixture qa-grouped-findings
claim slice-1-implementer implementer
"$SLICE_STATE" "$PLAN" 1 implementing >/dev/null
"$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$IMPLEMENTER" >/dev/null
claim slice-1-cleaner cleaner
"$SLICE_STATE" "$PLAN" 1 verifying-architect "$CLEANER" "$ZERO_FINDINGS_DIR" >/dev/null
claim slice-1-architect architect
"$SLICE_STATE" "$PLAN" 1 verifying-security "$ARCHITECT" "$ZERO_FINDINGS_DIR" >/dev/null
claim slice-1-security security-reviewer
"$SLICE_STATE" "$PLAN" 1 verifying-hardener "$SECURITY" "$ZERO_FINDINGS_DIR" >/dev/null
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

make_fixture repair
claim slice-1-implementer implementer
"$SLICE_STATE" "$PLAN" 1 implementing >/dev/null
"$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$IMPLEMENTER" >/dev/null
claim slice-1-cleaner cleaner
"$SLICE_STATE" "$PLAN" 1 verifying-architect "$CLEANER" "$ZERO_FINDINGS_DIR" >/dev/null
claim slice-1-architect architect
"$SLICE_STATE" "$PLAN" 1 verifying-security "$ARCHITECT" "$ZERO_FINDINGS_DIR" >/dev/null
claim slice-1-security security-reviewer
FINDING_REPORT="$TEST_ROOT/finding.md"
FINDING_REPORT_DIR="$TEST_ROOT/security-findings"
mkdir -p "$FINDING_REPORT_DIR"
printf '%s\n' \
  'Status: FINDINGS' \
  'Finding count: 1' >"$FINDING_REPORT"
printf '%s\n' \
  'Origin role: Security Reviewer' \
  'Severity claim: Important' \
  'Blocking claim: yes' \
  'Observed failure: Replay coverage is incomplete.' \
  'Evidence: reports/security.md' \
  'Violated authority: approved design' \
  'Assumptions: The replay table is authoritative.' \
  'Failure scenario: A stale review is accepted.' \
  'Proposed repair: Replay through Security Reviewer.' \
  'Repair effects: Cleaner through Security Reviewer rerun.' >"$FINDING_REPORT_DIR/1.md"
"$SLICE_STATE" "$PLAN" 1 verifying-hardener "$FINDING_REPORT" "$FINDING_REPORT_DIR" >/dev/null
finding_id=$(awk -F '\t' '$3 == "Security Reviewer" { print $1; exit }' "$WORKSPACE/findings.tsv")
[ -n "$finding_id" ] || record_fail 'Security finding is recorded by grouped acceptance'
claim "finding-$finding_id-dispose" controller
REPAIRING="$TEST_ROOT/repairing.md"
printf 'Repair hypothesis: Replay the affected roles.\nRepair base: %s\nReplay through: Security Reviewer\n' "$(git -C "$REPO" rev-parse HEAD)" >"$REPAIRING"
expect_success 'finding enters REPAIRING through its receipt' "$FINDING_STATE" "$PLAN" transition "$finding_id" REPAIRING "$REPAIRING"
claim "finding-$finding_id-replay-entry" controller
expect_success 'repair entry projects REPAIRING' "$SLICE_STATE" "$PLAN" 1 repairing "$FIXER" "$finding_id"
expect_contains 'REPAIRING is projected' "$TASKS" '**Slice state:** [~] REPAIRING'
claim "finding-$finding_id-repair-start-1" fixer
REPAIR_START="$TEST_ROOT/repair-start.md"
printf 'Repair round: 1\nExecutor: fixer\nAgent ID: fixer-one\nRepair hypothesis: Replay the affected roles.\n' >"$REPAIR_START"
expect_success 'repair round starts through its receipt' "$FINDING_STATE" "$PLAN" repair-start "$finding_id" "$REPAIR_START"
claim "finding-$finding_id-repair-finish-1" fixer
REPLAY="$TEST_ROOT/replay.md"
printf 'Replay verified.\n' >"$REPLAY"
REPAIR_FINISH="$TEST_ROOT/repair-finish.md"
printf 'Repair round: 1\nExecutor: fixer\nAgent ID: fixer-one\nRepair head: %s\nReplay status: VERIFIED\nReplay evidence: %s\n' "$(git -C "$REPO" rev-parse HEAD)" "$REPLAY" >"$REPAIR_FINISH"
expect_success 'repair finish records verified replay' "$FINDING_STATE" "$PLAN" repair-finish "$finding_id" "$REPAIR_FINISH"

# Break caught: a verified repair-finish alone cannot resolve while its required static replay is incomplete.
expect_failure 'resolution is not claimable before required replay completion' \
  "$WORKFLOW_STATE" "$PLAN" claim "finding-$finding_id-resolve" controller "$DISPATCH"
claim "finding-$finding_id-repair-result" fixer
expect_success 'repair acceptance starts the required replay at Cleaner' "$SLICE_STATE" "$PLAN" 1 verifying-cleaner "$FIXER"
expect_contains 'repair replay projects Cleaner' "$TASKS" '**Slice state:** [~] VERIFYING: CLEANER'
claim slice-1-cleaner cleaner
expect_success 'repair replay accepts fresh Cleaner evidence' "$SLICE_STATE" "$PLAN" 1 verifying-architect "$CLEANER" "$ZERO_FINDINGS_DIR"
claim slice-1-architect architect
expect_success 'repair replay accepts fresh Architect evidence' "$SLICE_STATE" "$PLAN" 1 verifying-security "$ARCHITECT" "$ZERO_FINDINGS_DIR"
claim slice-1-security security-reviewer
expect_success 'repair replay reaches the recorded Security endpoint' "$SLICE_STATE" "$PLAN" 1 verifying-hardener "$SECURITY" "$ZERO_FINDINGS_DIR"
claim "finding-$finding_id-resolve" controller
expect_success 'verified repair resolves after required replay completion' "$FINDING_STATE" "$PLAN" transition "$finding_id" RESOLVED "$REPAIR_FINISH"

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
