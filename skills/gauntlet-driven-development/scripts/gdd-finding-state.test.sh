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
Fable result: ${FABLE:-reports/fable-dismissal.md}
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

# The mutation that this test catches validates a transition before waiting on
# the workspace lock, then writes it after another transition has changed state.
race_id=$("$SCRIPT" "$PLAN" report 5 'Security Reviewer' "$FULL_REPORT") || race_id=''
[ -n "$race_id" ] && record_pass 'race fixture report is recorded' || record_fail 'race fixture report is recorded'
lock_dir="$WORKSPACE/.gdd-finding-state.lock"
mkdir "$lock_dir"
"$SCRIPT" "$PLAN" transition "$race_id" DISMISSED "$TERMINAL_RULING" >"$TEST_ROOT/race-dismissed.out" 2>"$TEST_ROOT/race-dismissed.err" &
race_dismissed_pid=$!
RACE_PARKED="$REPORTS/race-parked.md"
write_terminal_ruling "$RACE_PARKED" PARKED
"$SCRIPT" "$PLAN" transition "$race_id" PARKED "$RACE_PARKED" >"$TEST_ROOT/race-parked.out" 2>"$TEST_ROOT/race-parked.err" &
race_parked_pid=$!
sleep 1
rmdir "$lock_dir"
wait "$race_dismissed_pid" || true
wait "$race_parked_pid" || true
race_states=$(awk -F '\t' -v id="$race_id" '$1 == id { printf "%s ", $4 }' "$WORKSPACE/findings.tsv")
case "$race_states" in
  'REPORTED DISMISSED '|\
  'REPORTED PARKED ') record_pass 'serialized transitions revalidate the current state after recovery' ;;
  *) record_fail "serialized transitions revalidate the current state after recovery ($race_states)" ;;
esac

repair_id=$("$SCRIPT" "$PLAN" report 6 'Security Reviewer' "$FULL_REPORT") || repair_id=''
expect_success 'repair fixture enters REPAIRING' \
  "$SCRIPT" "$PLAN" transition "$repair_id" REPAIRING "$REPAIRING"
expect_success 'repair fixture starts round one' \
  "$SCRIPT" "$PLAN" repair-start "$repair_id" "$REPAIR_START"
REPAIR_FAILED="$REPORTS/repair-failed.md"
cat >"$REPAIR_FAILED" <<EOF
Repair round: 1
Executor: fixer
Agent ID: fixer-one
Repair head: $(git -C "$REPO" rev-parse HEAD)
Replay status: FAILED
Replay evidence: $REPLAY
EOF
expect_success 'repair fixture records one failed round' \
  "$SCRIPT" "$PLAN" repair-finish "$repair_id" "$REPAIR_FAILED"
expect_failure 'repair-finish rejects a second finish for the same round' \
  "$SCRIPT" "$PLAN" repair-finish "$repair_id" "$REPAIR_FAILED"

REPAIR_START_SAME="$REPORTS/repair-start-same.md"
cat >"$REPAIR_START_SAME" <<'EOF'
Repair round: 2
Executor: fixer-max
Agent ID: fixer-two
Repair hypothesis: Add the preflight before the Git-filter invocation.
EOF
expect_failure 'later repair rounds reject the unchanged failed hypothesis' \
  "$SCRIPT" "$PLAN" repair-start "$repair_id" "$REPAIR_START_SAME"
FALSIFYING_EVIDENCE="$REPORTS/falsifying-evidence.md"
printf '%s\n' 'The round-one premise is false because the preflight already runs before the filter.' >"$FALSIFYING_EVIDENCE"
cat >>"$REPAIR_START_SAME" <<EOF
Falsifying evidence: $FALSIFYING_EVIDENCE
Falsifies prior hypothesis: The recorded trace proves the proposed preflight already ran.
EOF
expect_success 'later repair rounds accept immutable evidence that falsifies the failed hypothesis' \
  "$SCRIPT" "$PLAN" repair-start "$repair_id" "$REPAIR_START_SAME"

prepare_interrupted_init() {
  fixture_name=$1
  phase=$2
  fixture_plan="$REPO/openspec/changes/$fixture_name/plan.md"
  fixture_workspace="$REPO/.superpowers/gdd/$fixture_name"
  fixture_stage="$fixture_workspace/.finding-stage.fixture"
  mkdir -p "$(dirname "$fixture_plan")" "$fixture_stage/findings"
  printf '%s\n' '# Interrupted init fixture' >"$fixture_plan"
  printf '%s\n' "pinned policy $fixture_name" >"$fixture_stage/finding-policy.md"
  shasum -a 256 "$fixture_stage/finding-policy.md" | awk '{ print $1 }' >"$fixture_stage/finding-policy.sha256"
  : >"$fixture_stage/findings.tsv"
  policy_sha=$(cat "$fixture_stage/finding-policy.sha256")
  digest_sha=$(shasum -a 256 "$fixture_stage/finding-policy.sha256" | awk '{ print $1 }')
  ledger_sha=$(shasum -a 256 "$fixture_stage/findings.tsv" | awk '{ print $1 }')
  printf 'staged_policy\t%s\nfinal_policy\t%s\npolicy_sha\t%s\nstaged_digest\t%s\nfinal_digest\t%s\ndigest_sha\t%s\nstaged_findings\t%s\nfinal_findings\t%s\nstaged_event\t-\nfinal_event\t-\nstaged_ledger\t%s\nledger_sha\t%s\nstaged_output\t-\nfinal_output\t-\noutput_sha\t-\n' \
    "$fixture_stage/finding-policy.md" "$fixture_workspace/finding-policy.md" "$policy_sha" \
    "$fixture_stage/finding-policy.sha256" "$fixture_workspace/finding-policy.sha256" "$digest_sha" \
    "$fixture_stage/findings" "$fixture_workspace/findings" "$fixture_stage/findings.tsv" "$ledger_sha" >"$fixture_workspace/.finding-journal"
  case "$phase" in
    before-artifact) ;;
    between-artifact-and-ledger)
      mv "$fixture_stage/finding-policy.md" "$fixture_workspace/finding-policy.md"
      mv "$fixture_stage/finding-policy.sha256" "$fixture_workspace/finding-policy.sha256"
      mv "$fixture_stage/findings" "$fixture_workspace/findings"
      ;;
    after-ledger)
      mv "$fixture_stage/finding-policy.md" "$fixture_workspace/finding-policy.md"
      mv "$fixture_stage/finding-policy.sha256" "$fixture_workspace/finding-policy.sha256"
      mv "$fixture_stage/findings" "$fixture_workspace/findings"
      mv "$fixture_stage/findings.tsv" "$fixture_workspace/findings.tsv"
      ;;
  esac
}

for init_phase in before-artifact between-artifact-and-ledger after-ledger; do
  init_fixture="recovery-$init_phase"
  prepare_interrupted_init "$init_fixture" "$init_phase"
  init_plan="$REPO/openspec/changes/$init_fixture/plan.md"
  init_workspace="$REPO/.superpowers/gdd/$init_fixture"
  expect_success "init recovers $init_phase publication exactly once" \
    "$SCRIPT" "$init_plan" init
  [ "$(cat "$init_workspace/finding-policy.md")" = "pinned policy $init_fixture" ] && record_pass "init preserves the staged snapshot for $init_phase" || record_fail "init preserves the staged snapshot for $init_phase"
  [ ! -e "$init_workspace/.finding-journal" ] && record_pass "init clears the recovered journal for $init_phase" || record_fail "init clears the recovered journal for $init_phase"
done

missing_fixture='recovery-missing-material'
prepare_interrupted_init "$missing_fixture" before-artifact
missing_plan="$REPO/openspec/changes/$missing_fixture/plan.md"
missing_workspace="$REPO/.superpowers/gdd/$missing_fixture"
missing_before=$(workspace_hash "$missing_workspace")
rm "$missing_workspace/.finding-stage.fixture/findings.tsv"
expect_failure 'init fails closed when an interrupted transaction loses staged ledger material' \
  "$SCRIPT" "$missing_plan" init
missing_after=$(workspace_hash "$missing_workspace")
[ "$missing_before" != "$missing_after" ] && record_pass 'missing staged material is detected before an incomplete ledger is published' || record_fail 'missing staged material is detected before an incomplete ledger is published'

for terminal_state in DEFERRED DISMISSED PARKED BLOCKED; do
  terminal_report="$REPORTS/terminal-$terminal_state.md"
  write_terminal_ruling "$terminal_report" "$terminal_state"
  terminal_id=$("$SCRIPT" "$PLAN" report 7 'Security Reviewer' "$FULL_REPORT") || terminal_id=''
  expect_success "REPORTED transitions to $terminal_state" \
    "$SCRIPT" "$PLAN" transition "$terminal_id" "$terminal_state" "$terminal_report"
  expect_success "$terminal_state transitions back to REPORTED" \
    "$SCRIPT" "$PLAN" transition "$terminal_id" REPORTED "$WAKE"
done

for repair_terminal_state in DEFERRED DISMISSED PARKED BLOCKED; do
  repair_terminal_report="$REPORTS/repair-terminal-$repair_terminal_state.md"
  write_terminal_ruling "$repair_terminal_report" "$repair_terminal_state"
  repair_terminal_id=$("$SCRIPT" "$PLAN" report 8 'Security Reviewer' "$FULL_REPORT") || repair_terminal_id=''
  expect_success "repair terminal fixture enters REPAIRING for $repair_terminal_state" \
    "$SCRIPT" "$PLAN" transition "$repair_terminal_id" REPAIRING "$REPAIRING"
  expect_success "REPAIRING transitions to $repair_terminal_state" \
    "$SCRIPT" "$PLAN" transition "$repair_terminal_id" "$repair_terminal_state" "$repair_terminal_report"
done

illegal_id=$("$SCRIPT" "$PLAN" report 9 'Security Reviewer' "$FULL_REPORT") || illegal_id=''
illegal_before=$(workspace_hash "$WORKSPACE")
expect_failure 'REPORTED rejects an illegal direct RESOLVED transition' \
  "$SCRIPT" "$PLAN" transition "$illegal_id" RESOLVED "$REPAIR_FINISH"
illegal_after=$(workspace_hash "$WORKSPACE")
[ "$illegal_before" = "$illegal_after" ] && record_pass 'illegal transition leaves the workspace unchanged' || record_fail 'illegal transition leaves the workspace unchanged'

FEATURE_REPAIRING="$REPORTS/feature-repairing.md"
cat >"$FEATURE_REPAIRING" <<EOF
Repair hypothesis: The branch review did not replay slice two.
Repair base: $(git -C "$REPO" rev-parse HEAD)
Replay through: QA
Affected slices: 2
EOF
feature_report="$REPORTS/branch-reviewer.md"
write_report "$feature_report" 'Branch Reviewer'
feature_id=$("$SCRIPT" "$PLAN" report feature 'Branch Reviewer' "$feature_report") || feature_id=''
expect_success 'feature Branch Reviewer finding enters REPAIRING with affected slices' \
  "$SCRIPT" "$PLAN" transition "$feature_id" REPAIRING "$FEATURE_REPAIRING"
expect_success 'repair-entry accepts a feature finding that names the requested slice' \
  "$SCRIPT" "$PLAN" repair-entry 2 "$feature_id"
direct_reentry_id=$("$SCRIPT" "$PLAN" report 10 'Security Reviewer' "$FULL_REPORT") || direct_reentry_id=''
expect_success 'direct verified re-entry fixture enters REPAIRING' \
  "$SCRIPT" "$PLAN" transition "$direct_reentry_id" REPAIRING "$REPAIRING"
expect_failure 'verified re-entry rejects a finding without a terminal wake history' \
  "$SCRIPT" "$PLAN" repair-entry 10 "$direct_reentry_id" verified-reentry

DIGEST_PLAN="$REPO/openspec/changes/digest-ledger/plan.md"
mkdir -p "$(dirname "$DIGEST_PLAN")"
printf '%s\n' '# Digest fixture' >"$DIGEST_PLAN"
expect_success 'digest fixture initializes independently' "$SCRIPT" "$DIGEST_PLAN" init
DIGEST_WORKSPACE="$REPO/.superpowers/gdd/digest-ledger"
expect_success 'digest writes None when no finding remains unchanged' \
  "$SCRIPT" "$DIGEST_PLAN" digest "$DIGEST_WORKSPACE/none.md"
expect_contains 'empty digest contains None' "$DIGEST_WORKSPACE/none.md" 'None.'
for digest_state in DEFERRED DISMISSED PARKED; do
  digest_terminal="$REPORTS/digest-$digest_state.md"
  write_terminal_ruling "$digest_terminal" "$digest_state"
  digest_id=$("$SCRIPT" "$DIGEST_PLAN" report 11 'Security Reviewer' "$FULL_REPORT") || digest_id=''
  expect_success "digest fixture records $digest_state" \
    "$SCRIPT" "$DIGEST_PLAN" transition "$digest_id" "$digest_state" "$digest_terminal"
done
expect_success 'digest writes each unchanged terminal disposition once' \
  "$SCRIPT" "$DIGEST_PLAN" digest "$DIGEST_WORKSPACE/findings.md"
for expected_digest_id in GDD-F0001 GDD-F0002 GDD-F0003; do
  expect_contains "digest includes $expected_digest_id" "$DIGEST_WORKSPACE/findings.md" "\`$expected_digest_id\`"
done

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
