#!/usr/bin/env bash
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/gdd-finding-state"
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
  [ -s "$TEST_ROOT/stderr" ] && sed 's/^/      stderr: /' "$TEST_ROOT/stderr"
}

expect_success() {
  name=$1
  shift
  if "$@" >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr"; then
    record_pass "$name"
  else
    record_fail "$name"
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

expect_contains() {
  name=$1
  file=$2
  pattern=$3
  if grep -Fq -- "$pattern" "$file"; then
    record_pass "$name"
  else
    record_fail "$name"
    printf '      missing: %s\n' "$pattern"
  fi
}

workspace_hash() {
  workspace=$1
  (
    cd "$workspace" || exit 1
    find . -type f ! -name '.gdd-finding-state.lock' -print0 | sort -z | xargs -0 shasum -a 256
  ) | shasum -a 256 | awk '{ print $1 }'
}

write_report() {
  report=$1
  origin=$2
  cat >"$report" <<EOF
Origin role: $origin
Severity claim: Important
Blocking claim: yes
Observed failure: A trusted-local assumption was replaced with a hostile-local premise.
Evidence: reports/security.md
Violated authority: design.md threat model
Assumptions: The local repository and Git configuration are hostile.
Failure scenario: A process filter runs only under the excluded hostile-local premise.
Proposed repair: Add a clean and process-filter preflight.
Repair effects: Adds a subprocess and concurrency to the approved change.
EOF
}

write_terminal_ruling() {
  ruling=$1
  disposition=$2
  cat >"$ruling" <<EOF
Disposition: $disposition
Ruling: The approved threat model excludes a hostile local repository and Git configuration.
Cost if wrong: A hostile local process could influence the filtered Git input.
Wake condition: The approved threat model includes hostile local repository state.
Fable result: reports/fable-dismissal.md
EOF
}

REPO="$TEST_ROOT/repo"
CHANGE="$REPO/openspec/changes/finding-ledger"
PLAN="$CHANGE/plan.md"
REPORTS="$TEST_ROOT/reports"
mkdir -p "$CHANGE" "$REPORTS"
git -C "$TEST_ROOT" init -q repo
git -C "$REPO" config user.name 'Test Bot'
git -C "$REPO" config user.email 'test@example.com'
printf '%s\n' '# Finding ledger plan' >"$PLAN"
printf '%s\n' 'fixture' >"$REPO/README.md"
git -C "$REPO" add README.md openspec
git -C "$REPO" commit -qm 'chore: fixture'

FULL_REPORT="$REPORTS/full.md"
INCOMPLETE_REPORT="$REPORTS/incomplete.md"
MISSING_ORIGIN_REPORT="$REPORTS/missing-origin.md"
MISMATCH_REPORT="$REPORTS/mismatch.md"
TERMINAL_RULING="$REPORTS/terminal.md"
REPAIRING="$REPORTS/repairing.md"
REPAIR_START="$REPORTS/repair-start.md"
REPAIR_FINISH="$REPORTS/repair-finish.md"
WAKE="$REPORTS/wake.md"
FABLE="$REPORTS/fable-dismissal.md"
REPLAY="$REPORTS/replay.md"

write_report "$FULL_REPORT" 'Security Reviewer'
head -n 4 "$FULL_REPORT" >"$INCOMPLETE_REPORT"
tail -n +2 "$FULL_REPORT" >"$MISSING_ORIGIN_REPORT"
write_report "$MISMATCH_REPORT" Cleaner
write_terminal_ruling "$TERMINAL_RULING" DISMISSED
printf '%s\n' 'Fable agrees with the dismissal.' >"$FABLE"
printf '%s\n' 'Replay succeeded.' >"$REPLAY"
printf '%s\n' 'Wake evidence: a dependent slice uses the disputed premise.' >"$WAKE"
cd "$TEST_ROOT" || exit 1

expect_success 'init pins policy and creates finding storage' \
  "$SCRIPT" "$PLAN" init
WORKSPACE="$REPO/.superpowers/gdd/finding-ledger"
[ -s "$WORKSPACE/finding-policy.md" ] && record_pass 'init creates finding-policy.md' || record_fail 'init creates finding-policy.md'
[ -s "$WORKSPACE/finding-policy.sha256" ] && record_pass 'init creates finding-policy.sha256' || record_fail 'init creates finding-policy.sha256'
[ -f "$WORKSPACE/findings.tsv" ] && record_pass 'init creates findings.tsv' || record_fail 'init creates findings.tsv'
[ -d "$WORKSPACE/findings" ] && record_pass 'init creates findings directory' || record_fail 'init creates findings directory'

expect_success 'repeated init accepts the pinned snapshot' \
  "$SCRIPT" "$PLAN" init
expect_success 'repeated init continues to use the pinned snapshot' \
  "$SCRIPT" "$PLAN" init

before_hash=$(workspace_hash "$WORKSPACE")
expect_failure 'report rejects a missing Origin role without mutation' \
  "$SCRIPT" "$PLAN" report 1 'Security Reviewer' "$MISSING_ORIGIN_REPORT"
after_hash=$(workspace_hash "$WORKSPACE")
[ "$before_hash" = "$after_hash" ] && record_pass 'invalid report leaves workspace unchanged' || record_fail 'invalid report leaves workspace unchanged'

finding_id=$("$SCRIPT" "$PLAN" report 1 'Security Reviewer' "$FULL_REPORT") || finding_id=''
[ "$finding_id" = 'GDD-F0001' ] && record_pass 'complete report returns first sequential ID' || record_fail 'complete report returns first sequential ID'
expect_contains 'report records REPORTED state' "$WORKSPACE/findings.tsv" $'GDD-F0001\t1\tSecurity Reviewer\tREPORTED\t'

expect_failure 'feature scope rejects a non-Branch Reviewer origin' \
  "$SCRIPT" "$PLAN" report feature 'Security Reviewer' "$FULL_REPORT"
expect_failure 'slice scope rejects a Branch Reviewer origin' \
  "$SCRIPT" "$PLAN" report 1 'Branch Reviewer' "$FULL_REPORT"
expect_failure 'report rejects mismatched Origin role' \
  "$SCRIPT" "$PLAN" report 2 'Security Reviewer' "$MISMATCH_REPORT"

for origin in Cleaner Architect Hardener QA 'Branch Reviewer'; do
  scope=2
  [ "$origin" = 'Branch Reviewer' ] && scope=feature
  report="$REPORTS/${origin// /-}.md"
  write_report "$report" "$origin"
  expect_success "report accepts $origin" \
    "$SCRIPT" "$PLAN" report "$scope" "$origin" "$report"
done

cat >"$REPAIRING" <<EOF
Repair hypothesis: The preflight is absent from the path that uses Git filters.
Repair base: $(git -C "$REPO" rev-parse HEAD)
Replay through: Security Reviewer
EOF
expect_success 'complete report enters REPAIRING with required evidence' \
  "$SCRIPT" "$PLAN" transition GDD-F0001 REPAIRING "$REPAIRING"
expect_success 'repairing finding admits replay through Security' \
  "$SCRIPT" "$PLAN" guard 1 verifying-security
expect_failure 'repairing finding blocks the next lifecycle target' \
  "$SCRIPT" "$PLAN" guard 1 verifying-hardener

cat >"$REPAIR_START" <<'EOF'
Repair round: 1
Executor: fixer
Agent ID: fixer-one
Repair hypothesis: Add the preflight before the Git-filter invocation.
EOF
expect_success 'repair-start accepts first fixer round' \
  "$SCRIPT" "$PLAN" repair-start GDD-F0001 "$REPAIR_START"
expect_failure 'repair-start rejects a second active round' \
  "$SCRIPT" "$PLAN" repair-start GDD-F0001 "$REPAIR_START"

git -C "$REPO" commit --allow-empty -qm 'fix: repair fixture'
cat >"$REPAIR_FINISH" <<EOF
Repair round: 1
Executor: fixer
Agent ID: fixer-one
Repair head: $(git -C "$REPO" rev-parse HEAD)
Replay status: VERIFIED
Replay evidence: $REPLAY
EOF
expect_success 'repair-finish accepts a verified descended commit' \
  "$SCRIPT" "$PLAN" repair-finish GDD-F0001 "$REPAIR_FINISH"
expect_success 'RESOLVED requires verified repair replay' \
  "$SCRIPT" "$PLAN" transition GDD-F0001 RESOLVED "$REPAIR_FINISH"

incomplete_id=$("$SCRIPT" "$PLAN" report 4 'Security Reviewer' "$INCOMPLETE_REPORT") || incomplete_id=''
[ "$incomplete_id" = 'GDD-F0007' ] && record_pass 'incomplete report remains recorded' || record_fail 'incomplete report remains recorded'
expect_failure 'incomplete report cannot leave REPORTED before supplement' \
  "$SCRIPT" "$PLAN" transition "$incomplete_id" REPAIRING "$REPAIRING"
expect_success 'supplement supplies the controller-verified report fields' \
  "$SCRIPT" "$PLAN" supplement "$incomplete_id" "$FULL_REPORT"
expect_success 'supplemented report can receive a terminal ruling' \
  "$SCRIPT" "$PLAN" transition "$incomplete_id" DISMISSED "$TERMINAL_RULING"

finding_two=$("$SCRIPT" "$PLAN" report 3 'Security Reviewer' "$FULL_REPORT") || finding_two=''
[ "$finding_two" = 'GDD-F0008' ] && record_pass 'IDs remain sequential across origins' || record_fail 'IDs remain sequential across origins'
expect_success 'terminal disposition accepts a complete ruling' \
  "$SCRIPT" "$PLAN" transition "$finding_two" DISMISSED "$TERMINAL_RULING"
expect_success 'wake transition requires immutable wake evidence' \
  "$SCRIPT" "$PLAN" transition "$finding_two" REPORTED "$WAKE"

before_hash=$(workspace_hash "$WORKSPACE")
expect_failure 'guard does not create a workspace for an unknown plan' \
  "$SCRIPT" "$REPO/unknown.md" guard 1 verifying-cleaner
after_hash=$(workspace_hash "$WORKSPACE")
[ "$before_hash" = "$after_hash" ] && record_pass 'read-only failure leaves workspace unchanged' || record_fail 'read-only failure leaves workspace unchanged'

expect_failure 'digest rejects remaining REPORTED findings' \
  "$SCRIPT" "$PLAN" digest "$WORKSPACE/findings.md"

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
