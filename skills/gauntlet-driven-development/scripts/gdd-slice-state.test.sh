#!/usr/bin/env bash
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/gdd-slice-state"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

pass=0
fail=0

record_pass() {
  pass=$((pass + 1))
  printf 'PASS  %s\n' "$1"
}

record_fail() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
}

expect_success() {
  name=$1
  shift
  if "$@" >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr"; then
    record_pass "$name"
  else
    record_fail "$name"
    printf '      stderr: %s\n' "$(cat "$TEST_ROOT/stderr")"
  fi
}

expect_failure() {
  name=$1
  shift
  if "$@" >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr"; then
    record_fail "$name"
  else
    record_pass "$name"
  fi
}

expect_file_contains() {
  name=$1
  file=$2
  pattern=$3
  if grep -qF -- "$pattern" "$file"; then
    record_pass "$name"
  else
    record_fail "$name"
    printf '      missing: %s\n' "$pattern"
  fi
}

expect_file_not_contains() {
  name=$1
  file=$2
  pattern=$3
  if grep -qF -- "$pattern" "$file"; then
    record_fail "$name"
    printf '      unexpected: %s\n' "$pattern"
  else
    record_pass "$name"
  fi
}

REPO="$TEST_ROOT/repo"
CHANGE="$REPO/openspec/changes/reset-password"
PLAN="$CHANGE/plan.md"
TASKS="$CHANGE/tasks.md"
mkdir -p "$CHANGE"
git -C "$REPO" init -q

printf '%s\n' '# Reset password plan' >"$PLAN"
printf '%s\n' \
  '## 1. User can reset their password' \
  '**Slice state:** [ ] QUEUED' \
  '' \
  '- [ ] 1.1 Add the password-reset domain behavior' \
  '- [ ] 1.2 Add the user-facing reset workflow' \
  '- [ ] 1.V **Slice verification gate**' \
  '' \
  '## 2. User can recover an expired reset link' \
  '**Slice state:** [ ] QUEUED' \
  '' \
  '- [ ] 2.1 Add the expired-link workflow' \
  '- [ ] 2.V **Slice verification gate**' >"$TASKS"

IMPLEMENTER_REPORT="$TEST_ROOT/implementer.md"
CLEANER_REPORT="$TEST_ROOT/cleaner.md"
ARCHITECT_REPORT="$TEST_ROOT/architect.md"
SECURITY_REPORT="$TEST_ROOT/security.md"
HARDENER_REPORT="$TEST_ROOT/hardener.md"
QA_REPORT="$TEST_ROOT/qa.md"
SUITE_REPORT="$TEST_ROOT/suite.md"
FINDING_REPORT="$TEST_ROOT/finding.md"
FIXER_REPORT="$TEST_ROOT/fixer.md"

printf '%s\n' 'Status: IMPLEMENTED' >"$IMPLEMENTER_REPORT"
printf '%s\n' 'Status: COMPLETE' >"$CLEANER_REPORT"
printf '%s\n' 'Status: COMPLETE' >"$ARCHITECT_REPORT"
printf '%s\n' 'Status: CLEAN' >"$SECURITY_REPORT"
printf '%s\n' 'Status: VERIFIED' >"$HARDENER_REPORT"
printf '%s\n' 'Status: VERIFIED' >"$QA_REPORT"
printf '%s\n' 'Status: PASS' >"$SUITE_REPORT"
printf '%s\n' 'Status: FINDINGS' >"$FINDING_REPORT"
printf '%s\n' 'Status: FIXED' >"$FIXER_REPORT"

expect_success 'queued slice enters implementation' \
  "$SCRIPT" "$PLAN" 1 implementing
expect_file_contains 'tasks records implementing state' \
  "$TASKS" '**Slice state:** [~] IMPLEMENTING'
expect_file_contains 'second slice remains untouched' \
  "$TASKS" '**Slice state:** [ ] QUEUED'

expect_failure 'slice cannot skip directly to verified' \
  "$SCRIPT" "$PLAN" 1 verified "$QA_REPORT" "$SUITE_REPORT"
expect_file_contains 'failed transition leaves gate open' \
  "$TASKS" '- [ ] 1.V **Slice verification gate**'

EMPTY_REPORT="$TEST_ROOT/empty.md"
: >"$EMPTY_REPORT"
expect_failure 'verification transition requires non-empty evidence' \
  "$SCRIPT" "$PLAN" 1 verifying-cleaner "$EMPTY_REPORT"
expect_success 'implementation evidence admits Cleaner' \
  "$SCRIPT" "$PLAN" 1 verifying-cleaner "$IMPLEMENTER_REPORT"
expect_success 'Cleaner evidence admits Architect' \
  "$SCRIPT" "$PLAN" 1 verifying-architect "$CLEANER_REPORT"
expect_success 'Architect evidence admits Security' \
  "$SCRIPT" "$PLAN" 1 verifying-security "$ARCHITECT_REPORT"

expect_failure 'Security findings cannot admit Hardener' \
  "$SCRIPT" "$PLAN" 1 verifying-hardener "$FINDING_REPORT"
expect_success 'clean Security verdict admits Hardener' \
  "$SCRIPT" "$PLAN" 1 verifying-hardener "$SECURITY_REPORT"

expect_success 'a finding routes the slice to repair' \
  "$SCRIPT" "$PLAN" 1 repairing "$FINDING_REPORT"
expect_file_contains 'repair state is visible' \
  "$TASKS" '**Slice state:** [~] REPAIRING'
expect_failure 'repair cannot skip Cleaner replay' \
  "$SCRIPT" "$PLAN" 1 verifying-architect "$FIXER_REPORT"
expect_success 'fixer evidence restarts at Cleaner' \
  "$SCRIPT" "$PLAN" 1 verifying-cleaner "$FIXER_REPORT"
expect_success 'Cleaner replay admits Architect' \
  "$SCRIPT" "$PLAN" 1 verifying-architect "$CLEANER_REPORT"
expect_success 'Architect replay admits Security' \
  "$SCRIPT" "$PLAN" 1 verifying-security "$ARCHITECT_REPORT"
expect_success 'fresh Security admits Hardener' \
  "$SCRIPT" "$PLAN" 1 verifying-hardener "$SECURITY_REPORT"

expect_failure 'non-verified Hardener report cannot admit QA' \
  "$SCRIPT" "$PLAN" 1 verifying-qa "$FINDING_REPORT"
expect_success 'verified Hardener report admits QA' \
  "$SCRIPT" "$PLAN" 1 verifying-qa "$HARDENER_REPORT"
expect_failure 'QA without VERIFIED cannot accept slice' \
  "$SCRIPT" "$PLAN" 1 verified "$FINDING_REPORT" "$SUITE_REPORT"
expect_failure 'failed final suite cannot accept slice' \
  "$SCRIPT" "$PLAN" 1 verified "$QA_REPORT" "$FINDING_REPORT"
expect_success 'QA and final suite evidence accept slice' \
  "$SCRIPT" "$PLAN" 1 verified "$QA_REPORT" "$SUITE_REPORT"

expect_file_contains 'accepted slice records verified state' \
  "$TASKS" '**Slice state:** [x] VERIFIED'
expect_file_contains 'accepted slice closes verification gate' \
  "$TASKS" '- [x] 1.V **Slice verification gate**'
expect_file_not_contains 'other slice gate remains open' \
  "$TASKS" '- [x] 2.V **Slice verification gate**'

LEDGER="$REPO/.superpowers/gdd/reset-password/ledger.tsv"
expect_file_contains 'ledger records repair transition' \
  "$LEDGER" $'1\tREPAIRING'
expect_file_contains 'ledger records final transition' \
  "$LEDGER" $'1\tVERIFIED'

expect_success 'repeating the current state is idempotent' \
  "$SCRIPT" "$PLAN" 1 verified "$QA_REPORT" "$SUITE_REPORT"
expect_failure 'unknown state is rejected' \
  "$SCRIPT" "$PLAN" 2 unknown-state
expect_failure 'missing slice is rejected' \
  "$SCRIPT" "$PLAN" 9 implementing

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
