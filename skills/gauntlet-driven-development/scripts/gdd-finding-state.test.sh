#!/usr/bin/env bash
set -u

SOURCE_DIR=$(cd "$(dirname "$0")" && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

# Run a byte-for-byte runtime copy so policy-resume tests can change the
# installed policy without touching the checkout under test.
RUNTIME_ROOT="$TEST_ROOT/runtime/skills/gauntlet-driven-development"
mkdir -p "$RUNTIME_ROOT/scripts"
cp "$SOURCE_DIR/gdd-finding-state" "$RUNTIME_ROOT/scripts/gdd-finding-state"
cp "$SOURCE_DIR/gdd-workspace" "$RUNTIME_ROOT/scripts/gdd-workspace"
cp "$SOURCE_DIR/../finding-policy.md" "$RUNTIME_ROOT/finding-policy.md"
SCRIPT="$RUNTIME_ROOT/scripts/gdd-finding-state"

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

expect_fault() {
  name=$1
  failpoint=$2
  shift 2
  if GDD_FINDING_STATE_FAILPOINT="$failpoint" "$@" >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr"; then
    record_fail "$name"
  elif grep -Fq "injected failure at $failpoint" "$TEST_ROOT/stderr"; then
    record_pass "$name"
  else
    record_fail "$name"
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
  repository=${workspace%%/.superpowers/gdd/*}
  workspace_slug=${workspace##*/}
  tasks_file="$repository/openspec/changes/$workspace_slug/tasks.md"
  gdd_gitignore="$repository/.superpowers/gdd/.gitignore"
  workspace_files_hash=$(
    cd "$workspace" || exit 1
    find . -type f ! -name '.gdd-finding-state.lock' -print0 | sort -z | xargs -0 shasum -a 256
  )
  {
    printf '%s\n' "$workspace_files_hash"
    file_hash_or_absent "$tasks_file"
    file_hash_or_absent "$gdd_gitignore"
  } | shasum -a 256 | awk '{ print $1 }'
}

file_hash_or_absent() {
  if [ -f "$1" ]; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    printf 'absent\n'
  fi
}

count_finding_rows() {
  finding_id=$1
  ledger_file=$2
  awk -F '\t' -v id="$finding_id" '$1 == id { count++ } END { print count + 0 }' "$ledger_file"
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
saved_policy_hash=$(file_hash_or_absent "$WORKSPACE/finding-policy.md")
printf '\nA later installed-policy revision.\n' >>"$RUNTIME_ROOT/finding-policy.md"
expect_success 'repeated init continues to use the pinned snapshot' \
  "$SCRIPT" "$PLAN" init
[ "$(file_hash_or_absent "$WORKSPACE/finding-policy.md")" = "$saved_policy_hash" ] && record_pass 'repeated init keeps the saved snapshot after an installed-policy change' || record_fail 'repeated init keeps the saved snapshot after an installed-policy change'

cp "$WORKSPACE/finding-policy.md" "$TEST_ROOT/saved-policy.md"
cp "$WORKSPACE/finding-policy.sha256" "$TEST_ROOT/saved-policy.sha256"
printf '\ncorrupt snapshot\n' >>"$WORKSPACE/finding-policy.md"
expect_failure 'repeated init rejects a changed saved snapshot' \
  "$SCRIPT" "$PLAN" init
cp "$TEST_ROOT/saved-policy.md" "$WORKSPACE/finding-policy.md"
printf '%s\n' 'not-the-saved-digest' >"$WORKSPACE/finding-policy.sha256"
expect_failure 'repeated init rejects a changed saved digest' \
  "$SCRIPT" "$PLAN" init
cp "$TEST_ROOT/saved-policy.sha256" "$WORKSPACE/finding-policy.sha256"

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
expect_failure 'slice scope rejects zero' \
  "$SCRIPT" "$PLAN" report 0 'Security Reviewer' "$FULL_REPORT"
expect_failure 'slice scope rejects a non-numeric value' \
  "$SCRIPT" "$PLAN" report slice-one 'Security Reviewer' "$FULL_REPORT"
expect_failure 'report rejects mismatched Origin role' \
  "$SCRIPT" "$PLAN" report 2 'Security Reviewer' "$MISMATCH_REPORT"

DUPLICATE_REPORT="$REPORTS/duplicate.md"
cp "$FULL_REPORT" "$DUPLICATE_REPORT"
printf '%s\n' 'Severity claim: Critical' >>"$DUPLICATE_REPORT"
before_hash=$(workspace_hash "$WORKSPACE")
expect_failure 'report rejects a duplicate field without mutation' \
  "$SCRIPT" "$PLAN" report 2 'Security Reviewer' "$DUPLICATE_REPORT"
[ "$before_hash" = "$(workspace_hash "$WORKSPACE")" ] && record_pass 'duplicate report field leaves workspace unchanged' || record_fail 'duplicate report field leaves workspace unchanged'

UNKNOWN_REPORT="$REPORTS/unknown.md"
cp "$FULL_REPORT" "$UNKNOWN_REPORT"
printf '%s\n' 'Review mood: concerned' >>"$UNKNOWN_REPORT"
before_hash=$(workspace_hash "$WORKSPACE")
expect_failure 'report rejects an unknown field without mutation' \
  "$SCRIPT" "$PLAN" report 2 'Security Reviewer' "$UNKNOWN_REPORT"
[ "$before_hash" = "$(workspace_hash "$WORKSPACE")" ] && record_pass 'unknown report field leaves workspace unchanged' || record_fail 'unknown report field leaves workspace unchanged'

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

write_repairing_evidence() {
  output_file=$1
  hypothesis=$2
  repair_base_value=$3
  replay_origin=$4
  affected_slices=${5:-}
  {
    printf 'Repair hypothesis: %s\n' "$hypothesis"
    printf 'Repair base: %s\n' "$repair_base_value"
    printf 'Replay through: %s\n' "$replay_origin"
    [ -z "$affected_slices" ] || printf 'Affected slices: %s\n' "$affected_slices"
  } >"$output_file"
}

REPAIR_MATRIX_PLAN="$REPO/openspec/changes/repair-matrix/plan.md"
mkdir -p "$(dirname "$REPAIR_MATRIX_PLAN")"
printf '%s\n' '# Repair matrix fixture' >"$REPAIR_MATRIX_PLAN"
expect_success 'repair matrix fixture initializes' "$SCRIPT" "$REPAIR_MATRIX_PLAN" init
REPAIR_MATRIX_WORKSPACE="$REPO/.superpowers/gdd/repair-matrix"
repair_matrix_id=$("$SCRIPT" "$REPAIR_MATRIX_PLAN" report 50 'Security Reviewer' "$FULL_REPORT") || repair_matrix_id=''
expect_success 'repair matrix finding enters REPAIRING' \
  "$SCRIPT" "$REPAIR_MATRIX_PLAN" transition "$repair_matrix_id" REPAIRING "$REPAIRING"

write_repair_start() {
  output_file=$1
  repair_round=$2
  executor_name=$3
  repair_agent=$4
  repair_hypothesis=$5
  cat >"$output_file" <<EOF
Repair round: $repair_round
Executor: $executor_name
Agent ID: $repair_agent
Repair hypothesis: $repair_hypothesis
EOF
}

write_repair_finish() {
  output_file=$1
  repair_round=$2
  executor_name=$3
  repair_agent=$4
  repair_head_value=$5
  replay_status=$6
  replay_evidence_value=$7
  cat >"$output_file" <<EOF
Repair round: $repair_round
Executor: $executor_name
Agent ID: $repair_agent
Repair head: $repair_head_value
Replay status: $replay_status
Replay evidence: $replay_evidence_value
EOF
}

REPAIR_MATRIX_START="$REPORTS/repair-matrix-start.md"
write_repair_start "$REPAIR_MATRIX_START" 1 fixer-max matrix-agent-1 'Round one has the wrong executor.'
before_hash=$(workspace_hash "$REPAIR_MATRIX_WORKSPACE")
expect_failure 'repair round 1 rejects fixer-max executor' \
  "$SCRIPT" "$REPAIR_MATRIX_PLAN" repair-start "$repair_matrix_id" "$REPAIR_MATRIX_START"
[ "$before_hash" = "$(workspace_hash "$REPAIR_MATRIX_WORKSPACE")" ] && record_pass 'invalid round 1 executor leaves workspace unchanged' || record_fail 'invalid round 1 executor leaves workspace unchanged'
write_repair_start "$REPAIR_MATRIX_START" 1 fixer matrix-agent-1 'Round one applies the first bounded repair.'
expect_success 'repair round 1 accepts fixer executor' \
  "$SCRIPT" "$REPAIR_MATRIX_PLAN" repair-start "$repair_matrix_id" "$REPAIR_MATRIX_START"
write_repair_start "$REPAIR_MATRIX_START" 2 fixer-max matrix-agent-2 'Round two changes the failed repair.'
expect_failure 'repair round 2 waits for the prior repair-finish' \
  "$SCRIPT" "$REPAIR_MATRIX_PLAN" repair-start "$repair_matrix_id" "$REPAIR_MATRIX_START"

REPAIR_MATRIX_FINISH="$REPORTS/repair-matrix-finish.md"
write_repair_finish "$REPAIR_MATRIX_FINISH" 1 fixer matrix-agent-1 "$(git -C "$REPO" rev-parse HEAD)" FAILED "$REPLAY"
expect_success 'repair round 1 records FAILED replay' \
  "$SCRIPT" "$REPAIR_MATRIX_PLAN" repair-finish "$repair_matrix_id" "$REPAIR_MATRIX_FINISH"

for matrix_round in 2 3 4 5; do
  matrix_agent="matrix-agent-$matrix_round"
  matrix_hypothesis="Round $matrix_round uses new evidence and a different bounded repair."
  write_repair_start "$REPAIR_MATRIX_START" "$matrix_round" fixer "$matrix_agent" "$matrix_hypothesis"
  before_hash=$(workspace_hash "$REPAIR_MATRIX_WORKSPACE")
  expect_failure "repair round $matrix_round rejects fixer executor" \
    "$SCRIPT" "$REPAIR_MATRIX_PLAN" repair-start "$repair_matrix_id" "$REPAIR_MATRIX_START"
  [ "$before_hash" = "$(workspace_hash "$REPAIR_MATRIX_WORKSPACE")" ] && record_pass "invalid round $matrix_round executor leaves workspace unchanged" || record_fail "invalid round $matrix_round executor leaves workspace unchanged"
  write_repair_start "$REPAIR_MATRIX_START" "$matrix_round" fixer-max matrix-agent-1 "$matrix_hypothesis"
  expect_failure "repair round $matrix_round rejects an Agent ID already used on the finding" \
    "$SCRIPT" "$REPAIR_MATRIX_PLAN" repair-start "$repair_matrix_id" "$REPAIR_MATRIX_START"
  write_repair_start "$REPAIR_MATRIX_START" "$matrix_round" fixer-max "$matrix_agent" "$matrix_hypothesis"
  expect_success "repair round $matrix_round accepts fixer-max and a fresh Agent ID" \
    "$SCRIPT" "$REPAIR_MATRIX_PLAN" repair-start "$repair_matrix_id" "$REPAIR_MATRIX_START"
  if [ "$matrix_round" -lt 5 ]; then
    write_repair_finish "$REPAIR_MATRIX_FINISH" "$matrix_round" fixer-max "$matrix_agent" "$(git -C "$REPO" rev-parse HEAD)" FAILED "$REPLAY"
    expect_success "repair round $matrix_round records FAILED replay" \
      "$SCRIPT" "$REPAIR_MATRIX_PLAN" repair-finish "$repair_matrix_id" "$REPAIR_MATRIX_FINISH"
  fi
done
write_repair_start "$REPAIR_MATRIX_START" 6 fixer-max matrix-agent-6 'A sixth attempt is outside the bounded protocol.'
expect_failure 'repair-start rejects round 6' \
  "$SCRIPT" "$REPAIR_MATRIX_PLAN" repair-start "$repair_matrix_id" "$REPAIR_MATRIX_START"

VERIFIED_ROUND_PLAN="$REPO/openspec/changes/verified-round/plan.md"
mkdir -p "$(dirname "$VERIFIED_ROUND_PLAN")"
printf '%s\n' '# Verified round fixture' >"$VERIFIED_ROUND_PLAN"
expect_success 'verified round fixture initializes' "$SCRIPT" "$VERIFIED_ROUND_PLAN" init
verified_round_id=$("$SCRIPT" "$VERIFIED_ROUND_PLAN" report 51 'Security Reviewer' "$FULL_REPORT") || verified_round_id=''
expect_success 'verified round fixture enters REPAIRING' "$SCRIPT" "$VERIFIED_ROUND_PLAN" transition "$verified_round_id" REPAIRING "$REPAIRING"
write_repair_start "$REPAIR_MATRIX_START" 1 fixer verified-agent-1 'Round one fully repairs the finding.'
expect_success 'verified round fixture starts round 1' "$SCRIPT" "$VERIFIED_ROUND_PLAN" repair-start "$verified_round_id" "$REPAIR_MATRIX_START"
write_repair_finish "$REPAIR_MATRIX_FINISH" 1 fixer verified-agent-1 "$(git -C "$REPO" rev-parse HEAD)" VERIFIED "$REPLAY"
expect_success 'verified round fixture finishes VERIFIED' "$SCRIPT" "$VERIFIED_ROUND_PLAN" repair-finish "$verified_round_id" "$REPAIR_MATRIX_FINISH"
write_repair_start "$REPAIR_MATRIX_START" 2 fixer-max verified-agent-2 'An unnecessary second repair.'
expect_failure 'a new repair round rejects a prior VERIFIED replay' \
  "$SCRIPT" "$VERIFIED_ROUND_PLAN" repair-start "$verified_round_id" "$REPAIR_MATRIX_START"

FEATURE_AGENT_PLAN="$REPO/openspec/changes/feature-agent-reuse/plan.md"
mkdir -p "$(dirname "$FEATURE_AGENT_PLAN")"
printf '%s\n' '# Feature agent reuse fixture' >"$FEATURE_AGENT_PLAN"
expect_success 'feature agent reuse fixture initializes' "$SCRIPT" "$FEATURE_AGENT_PLAN" init
FEATURE_AGENT_REPORT="$REPORTS/feature-agent-report.md"
write_report "$FEATURE_AGENT_REPORT" 'Branch Reviewer'
FEATURE_AGENT_REPAIRING="$REPORTS/feature-agent-repairing.md"
write_repairing_evidence "$FEATURE_AGENT_REPAIRING" 'Replay the combined branch repair.' "$(git -C "$REPO" rev-parse HEAD)" QA '1,2'
for feature_agent_number in 1 2; do
  feature_agent_id=$("$SCRIPT" "$FEATURE_AGENT_PLAN" report feature 'Branch Reviewer' "$FEATURE_AGENT_REPORT") || feature_agent_id=''
  expect_success "feature finding $feature_agent_number enters REPAIRING" \
    "$SCRIPT" "$FEATURE_AGENT_PLAN" transition "$feature_agent_id" REPAIRING "$FEATURE_AGENT_REPAIRING"
  write_repair_start "$REPAIR_MATRIX_START" 1 fixer combined-feature-agent 'One combined dispatch repairs both feature findings.'
  expect_success "combined feature dispatch reuses its actual Agent ID on finding $feature_agent_number" \
    "$SCRIPT" "$FEATURE_AGENT_PLAN" repair-start "$feature_agent_id" "$REPAIR_MATRIX_START"
done

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

for event_phase in before-artifact-publication between-artifact-and-ledger-publication after-ledger-publication; do
  event_fixture="event-$event_phase"
  event_plan="$REPO/openspec/changes/$event_fixture/plan.md"
  event_workspace="$REPO/.superpowers/gdd/$event_fixture"
  mkdir -p "$(dirname "$event_plan")"
  printf '%s\n' '# Event recovery fixture' >"$event_plan"
  expect_success "event recovery initializes $event_phase fixture" \
    "$SCRIPT" "$event_plan" init
  expect_fault "report interrupts at $event_phase" "$event_phase" \
    "$SCRIPT" "$event_plan" report 1 'Security Reviewer' "$FULL_REPORT"
  [ -f "$event_workspace/.finding-journal" ] && record_pass "report leaves a recovery journal at $event_phase" || record_fail "report leaves a recovery journal at $event_phase"
  expect_success "report transaction recovers exactly once from $event_phase" \
    "$SCRIPT" "$event_plan" init
  [ "$(count_finding_rows GDD-F0001 "$event_workspace/findings.tsv")" -eq 1 ] && record_pass "recovered report has one ledger row at $event_phase" || record_fail "recovered report has one ledger row at $event_phase"
  recovered_artifact=$(awk -F '\t' '$1 == "GDD-F0001" { print $6 }' "$event_workspace/findings.tsv")
  [ -s "$event_workspace/$recovered_artifact/evidence.md" ] && record_pass "recovered report row has immutable evidence at $event_phase" || record_fail "recovered report row has immutable evidence at $event_phase"
  [ ! -e "$event_workspace/.finding-journal" ] && record_pass "report recovery clears journal at $event_phase" || record_fail "report recovery clears journal at $event_phase"
  recovered_next_id=$("$SCRIPT" "$event_plan" report 2 'Security Reviewer' "$FULL_REPORT") || recovered_next_id=''
  [ "$recovered_next_id" = GDD-F0002 ] && record_pass "report recovery does not reuse an ID at $event_phase" || record_fail "report recovery does not reuse an ID at $event_phase"
done

for digest_phase in before-artifact-publication between-artifact-and-ledger-publication after-ledger-publication; do
  digest_recovery_fixture="digest-$digest_phase"
  digest_recovery_plan="$REPO/openspec/changes/$digest_recovery_fixture/plan.md"
  digest_recovery_workspace="$REPO/.superpowers/gdd/$digest_recovery_fixture"
  mkdir -p "$(dirname "$digest_recovery_plan")"
  printf '%s\n' '# Digest recovery fixture' >"$digest_recovery_plan"
  expect_success "digest recovery initializes $digest_phase fixture" \
    "$SCRIPT" "$digest_recovery_plan" init
  digest_recovery_id=$("$SCRIPT" "$digest_recovery_plan" report 1 'Security Reviewer' "$FULL_REPORT") || digest_recovery_id=''
  expect_success "digest recovery records a terminal finding for $digest_phase" \
    "$SCRIPT" "$digest_recovery_plan" transition "$digest_recovery_id" DISMISSED "$TERMINAL_RULING"
  digest_recovery_output="$digest_recovery_workspace/findings.md"
  expect_fault "digest interrupts at $digest_phase" "$digest_phase" \
    "$SCRIPT" "$digest_recovery_plan" digest "$digest_recovery_output"
  [ -f "$digest_recovery_workspace/.finding-journal" ] && record_pass "digest leaves a recovery journal at $digest_phase" || record_fail "digest leaves a recovery journal at $digest_phase"
  expect_success "digest transaction recovers exactly once from $digest_phase" \
    "$SCRIPT" "$digest_recovery_plan" init
  [ "$(grep -Fc "\`$digest_recovery_id\`" "$digest_recovery_output")" -eq 1 ] && record_pass "recovered digest contains its finding once at $digest_phase" || record_fail "recovered digest contains its finding once at $digest_phase"
  [ ! -e "$digest_recovery_workspace/.finding-journal" ] && record_pass "digest recovery clears journal at $digest_phase" || record_fail "digest recovery clears journal at $digest_phase"
done

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

MISSING_EVENT_PLAN="$REPO/openspec/changes/missing-event-material/plan.md"
mkdir -p "$(dirname "$MISSING_EVENT_PLAN")"
printf '%s\n' '# Missing event material fixture' >"$MISSING_EVENT_PLAN"
expect_success 'missing event fixture initializes' "$SCRIPT" "$MISSING_EVENT_PLAN" init
MISSING_EVENT_WORKSPACE="$REPO/.superpowers/gdd/missing-event-material"
missing_event_ledger_hash=$(file_hash_or_absent "$MISSING_EVENT_WORKSPACE/findings.tsv")
expect_fault 'report stops with a fully staged event transaction' before-artifact-publication \
  "$SCRIPT" "$MISSING_EVENT_PLAN" report 1 'Security Reviewer' "$FULL_REPORT"
missing_staged_event=$(sed -n $'s/^staged_event\t//p' "$MISSING_EVENT_WORKSPACE/.finding-journal")
missing_final_event=$(sed -n $'s/^final_event\t//p' "$MISSING_EVENT_WORKSPACE/.finding-journal")
rm -r "$missing_staged_event"
expect_failure 'event recovery fails closed when staged evidence is missing' \
  "$SCRIPT" "$MISSING_EVENT_PLAN" init
[ "$(file_hash_or_absent "$MISSING_EVENT_WORKSPACE/findings.tsv")" = "$missing_event_ledger_hash" ] && record_pass 'missing event material leaves the last complete ledger unchanged' || record_fail 'missing event material leaves the last complete ledger unchanged'
[ ! -e "$missing_final_event" ] && record_pass 'missing event material exposes no ledger artifact' || record_fail 'missing event material exposes no ledger artifact'
[ -f "$MISSING_EVENT_WORKSPACE/.finding-journal" ] && record_pass 'missing event material keeps the recovery journal' || record_fail 'missing event material keeps the recovery journal'

COMMAND_RECOVERY_PLAN="$REPO/openspec/changes/command-recovery/plan.md"
mkdir -p "$(dirname "$COMMAND_RECOVERY_PLAN")"
printf '%s\n' '# Mutating command recovery fixture' >"$COMMAND_RECOVERY_PLAN"
expect_success 'mutating command recovery fixture initializes' "$SCRIPT" "$COMMAND_RECOVERY_PLAN" init
COMMAND_RECOVERY_WORKSPACE="$REPO/.superpowers/gdd/command-recovery"
command_recovery_id=$("$SCRIPT" "$COMMAND_RECOVERY_PLAN" report 1 'Security Reviewer' "$INCOMPLETE_REPORT") || command_recovery_id=''
expect_fault 'supplement interruption uses the event transaction protocol' before-artifact-publication \
  "$SCRIPT" "$COMMAND_RECOVERY_PLAN" supplement "$command_recovery_id" "$FULL_REPORT"
expect_success 'supplement transaction recovers through init' "$SCRIPT" "$COMMAND_RECOVERY_PLAN" init
[ "$(find "$COMMAND_RECOVERY_WORKSPACE/findings/$command_recovery_id/events" -type d -name '*-supplement' | wc -l | tr -d ' ')" -eq 1 ] && record_pass 'supplement recovery publishes exactly one event' || record_fail 'supplement recovery publishes exactly one event'
expect_fault 'transition interruption uses the event transaction protocol' between-artifact-and-ledger-publication \
  "$SCRIPT" "$COMMAND_RECOVERY_PLAN" transition "$command_recovery_id" REPAIRING "$REPAIRING"
expect_success 'transition transaction recovers through init' "$SCRIPT" "$COMMAND_RECOVERY_PLAN" init
[ "$(count_finding_rows "$command_recovery_id" "$COMMAND_RECOVERY_WORKSPACE/findings.tsv")" -eq 3 ] && record_pass 'transition recovery publishes exactly one row' || record_fail 'transition recovery publishes exactly one row'
COMMAND_RECOVERY_START="$REPORTS/command-recovery-start.md"
cat >"$COMMAND_RECOVERY_START" <<'EOF'
Repair round: 1
Executor: fixer
Agent ID: command-recovery-fixer
Repair hypothesis: Exercise repair-start journal recovery.
EOF
expect_fault 'repair-start interruption uses the event transaction protocol' after-ledger-publication \
  "$SCRIPT" "$COMMAND_RECOVERY_PLAN" repair-start "$command_recovery_id" "$COMMAND_RECOVERY_START"
expect_success 'repair-start transaction recovers through init' "$SCRIPT" "$COMMAND_RECOVERY_PLAN" init
[ "$(find "$COMMAND_RECOVERY_WORKSPACE/findings/$command_recovery_id/events" -type d -name '*-repair-start' | wc -l | tr -d ' ')" -eq 1 ] && record_pass 'repair-start recovery publishes exactly one event' || record_fail 'repair-start recovery publishes exactly one event'
COMMAND_RECOVERY_FINISH="$REPORTS/command-recovery-finish.md"
cat >"$COMMAND_RECOVERY_FINISH" <<EOF
Repair round: 1
Executor: fixer
Agent ID: command-recovery-fixer
Repair head: $(git -C "$REPO" rev-parse HEAD)
Replay status: VERIFIED
Replay evidence: $REPLAY
EOF
expect_fault 'repair-finish interruption uses the event transaction protocol' before-artifact-publication \
  "$SCRIPT" "$COMMAND_RECOVERY_PLAN" repair-finish "$command_recovery_id" "$COMMAND_RECOVERY_FINISH"
expect_success 'repair-finish transaction recovers through init' "$SCRIPT" "$COMMAND_RECOVERY_PLAN" init
[ "$(find "$COMMAND_RECOVERY_WORKSPACE/findings/$command_recovery_id/events" -type d -name '*-repair-finish' | wc -l | tr -d ' ')" -eq 1 ] && record_pass 'repair-finish recovery publishes exactly one event' || record_fail 'repair-finish recovery publishes exactly one event'

VALIDATION_PLAN="$REPO/openspec/changes/validation-matrix/plan.md"
mkdir -p "$(dirname "$VALIDATION_PLAN")"
printf '%s\n' '# Validation matrix fixture' >"$VALIDATION_PLAN"
expect_success 'validation matrix fixture initializes' "$SCRIPT" "$VALIDATION_PLAN" init
VALIDATION_WORKSPACE="$REPO/.superpowers/gdd/validation-matrix"

validation_incomplete_id=$("$SCRIPT" "$VALIDATION_PLAN" report 1 'Security Reviewer' "$INCOMPLETE_REPORT") || validation_incomplete_id=''
before_hash=$(workspace_hash "$VALIDATION_WORKSPACE")
expect_failure 'supplement rejects a report that still omits required fields' \
  "$SCRIPT" "$VALIDATION_PLAN" supplement "$validation_incomplete_id" "$INCOMPLETE_REPORT"
[ "$before_hash" = "$(workspace_hash "$VALIDATION_WORKSPACE")" ] && record_pass 'invalid supplement leaves workspace unchanged' || record_fail 'invalid supplement leaves workspace unchanged'
N_A_REPORT="$REPORTS/n-a-report.md"
sed 's/^Repair effects:.*/Repair effects: N\/A:/' "$FULL_REPORT" >"$N_A_REPORT"
expect_failure 'supplement rejects N/A without a controller-verified reason' \
  "$SCRIPT" "$VALIDATION_PLAN" supplement "$validation_incomplete_id" "$N_A_REPORT"
sed 's/^Repair effects:.*/Repair effects: N\/A: The controller verified that dismissal changes no implementation./' "$FULL_REPORT" >"$N_A_REPORT"
expect_success 'supplement accepts a reasoned N/A value' \
  "$SCRIPT" "$VALIDATION_PLAN" supplement "$validation_incomplete_id" "$N_A_REPORT"

for repairing_error in missing-hypothesis missing-base invalid-base invalid-replay; do
  repairing_error_id=$("$SCRIPT" "$VALIDATION_PLAN" report 2 'Security Reviewer' "$FULL_REPORT") || repairing_error_id=''
  repairing_error_file="$REPORTS/repairing-$repairing_error.md"
  case "$repairing_error" in
    missing-hypothesis) write_repairing_evidence "$repairing_error_file" '' "$(git -C "$REPO" rev-parse HEAD)" 'Security Reviewer' ;;
    missing-base) write_repairing_evidence "$repairing_error_file" 'A concrete repair hypothesis.' '' 'Security Reviewer' ;;
    invalid-base) write_repairing_evidence "$repairing_error_file" 'A concrete repair hypothesis.' deadbeef 'Security Reviewer' ;;
    invalid-replay) write_repairing_evidence "$repairing_error_file" 'A concrete repair hypothesis.' "$(git -C "$REPO" rev-parse HEAD)" 'Branch Reviewer' ;;
  esac
  before_hash=$(workspace_hash "$VALIDATION_WORKSPACE")
  expect_failure "REPAIRING rejects $repairing_error evidence" \
    "$SCRIPT" "$VALIDATION_PLAN" transition "$repairing_error_id" REPAIRING "$repairing_error_file"
  [ "$before_hash" = "$(workspace_hash "$VALIDATION_WORKSPACE")" ] && record_pass "invalid REPAIRING $repairing_error leaves workspace unchanged" || record_fail "invalid REPAIRING $repairing_error leaves workspace unchanged"
done

for affected_error in missing duplicate zero unnormalized; do
  affected_report="$REPORTS/feature-$affected_error.md"
  write_report "$affected_report" 'Branch Reviewer'
  affected_id=$("$SCRIPT" "$VALIDATION_PLAN" report feature 'Branch Reviewer' "$affected_report") || affected_id=''
  affected_evidence="$REPORTS/feature-repairing-$affected_error.md"
  case "$affected_error" in
    missing) affected_value='' ;;
    duplicate) affected_value='2,2' ;;
    zero) affected_value='0' ;;
    unnormalized) affected_value='2, 3' ;;
  esac
  write_repairing_evidence "$affected_evidence" 'Replay the affected feature slices.' "$(git -C "$REPO" rev-parse HEAD)" QA "$affected_value"
  before_hash=$(workspace_hash "$VALIDATION_WORKSPACE")
  expect_failure "feature REPAIRING rejects $affected_error Affected slices" \
    "$SCRIPT" "$VALIDATION_PLAN" transition "$affected_id" REPAIRING "$affected_evidence"
  [ "$before_hash" = "$(workspace_hash "$VALIDATION_WORKSPACE")" ] && record_pass "invalid feature $affected_error leaves workspace unchanged" || record_fail "invalid feature $affected_error leaves workspace unchanged"
done

for terminal_field in Disposition Ruling 'Cost if wrong' 'Wake condition' 'Fable result'; do
  terminal_validation_id=$("$SCRIPT" "$VALIDATION_PLAN" report 3 'Security Reviewer' "$FULL_REPORT") || terminal_validation_id=''
  terminal_validation_file="$REPORTS/terminal-missing-${terminal_field// /-}.md"
  awk -v field="$terminal_field" 'index($0, field ":") != 1' "$TERMINAL_RULING" >"$terminal_validation_file"
  before_hash=$(workspace_hash "$VALIDATION_WORKSPACE")
  expect_failure "terminal disposition rejects missing $terminal_field" \
    "$SCRIPT" "$VALIDATION_PLAN" transition "$terminal_validation_id" DISMISSED "$terminal_validation_file"
  [ "$before_hash" = "$(workspace_hash "$VALIDATION_WORKSPACE")" ] && record_pass "missing terminal $terminal_field leaves workspace unchanged" || record_fail "missing terminal $terminal_field leaves workspace unchanged"
done

for fable_error in missing-file empty-file unavailable-without-reason; do
  fable_validation_id=$("$SCRIPT" "$VALIDATION_PLAN" report 4 'Security Reviewer' "$FULL_REPORT") || fable_validation_id=''
  fable_validation_file="$REPORTS/fable-$fable_error-ruling.md"
  case "$fable_error" in
    missing-file) invalid_fable="$REPORTS/does-not-exist.md" ;;
    empty-file) invalid_fable="$REPORTS/empty-fable.md"; : >"$invalid_fable" ;;
    unavailable-without-reason) invalid_fable='UNAVAILABLE:' ;;
  esac
  FABLE="$invalid_fable" write_terminal_ruling "$fable_validation_file" DISMISSED
  expect_failure "terminal disposition rejects Fable result $fable_error" \
    "$SCRIPT" "$VALIDATION_PLAN" transition "$fable_validation_id" DISMISSED "$fable_validation_file"
done
unavailable_id=$("$SCRIPT" "$VALIDATION_PLAN" report 4 'Security Reviewer' "$FULL_REPORT") || unavailable_id=''
UNAVAILABLE_RULING="$REPORTS/fable-unavailable-reason.md"
FABLE='UNAVAILABLE: Fable Advisor could not be reached after the required attempt.' write_terminal_ruling "$UNAVAILABLE_RULING" DISMISSED
expect_success 'terminal disposition accepts UNAVAILABLE with a reason' \
  "$SCRIPT" "$VALIDATION_PLAN" transition "$unavailable_id" DISMISSED "$UNAVAILABLE_RULING"

wake_validation_id=$("$SCRIPT" "$VALIDATION_PLAN" report 5 'Security Reviewer' "$FULL_REPORT") || wake_validation_id=''
expect_success 'wake validation fixture reaches DISMISSED' \
  "$SCRIPT" "$VALIDATION_PLAN" transition "$wake_validation_id" DISMISSED "$TERMINAL_RULING"
before_hash=$(workspace_hash "$VALIDATION_WORKSPACE")
expect_failure 'wake transition rejects evidence without Wake evidence' \
  "$SCRIPT" "$VALIDATION_PLAN" transition "$wake_validation_id" REPORTED "$TERMINAL_RULING"
[ "$before_hash" = "$(workspace_hash "$VALIDATION_WORKSPACE")" ] && record_pass 'invalid wake transition leaves workspace unchanged' || record_fail 'invalid wake transition leaves workspace unchanged'

for transition_terminal_state in DEFERRED DISMISSED PARKED BLOCKED; do
  transition_terminal_file="$REPORTS/illegal-$transition_terminal_state.md"
  write_terminal_ruling "$transition_terminal_file" "$transition_terminal_state"
done

is_legal_transition() {
  case "$1 -> $2" in
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
    'BLOCKED -> REPORTED') return 0 ;;
    *) return 1 ;;
  esac
}

prepare_illegal_state() {
  illegal_state=$1
  illegal_index=$2
  ILLEGAL_PLAN="$REPO/openspec/changes/illegal-$illegal_state/plan.md"
  ILLEGAL_WORKSPACE="$REPO/.superpowers/gdd/illegal-$illegal_state"
  mkdir -p "$(dirname "$ILLEGAL_PLAN")"
  printf '%s\n' "# Illegal transition fixture for $illegal_state" >"$ILLEGAL_PLAN"
  "$SCRIPT" "$ILLEGAL_PLAN" init >/dev/null 2>&1 || record_fail "prepare $illegal_state fixture init"
  ILLEGAL_ID=$("$SCRIPT" "$ILLEGAL_PLAN" report "$illegal_index" 'Security Reviewer' "$FULL_REPORT") || ILLEGAL_ID=''
  case "$illegal_state" in
    REPORTED) ;;
    REPAIRING)
      "$SCRIPT" "$ILLEGAL_PLAN" transition "$ILLEGAL_ID" REPAIRING "$REPAIRING" >/dev/null 2>&1 || record_fail 'prepare REPAIRING fixture transition'
      ;;
    RESOLVED)
      "$SCRIPT" "$ILLEGAL_PLAN" transition "$ILLEGAL_ID" REPAIRING "$REPAIRING" >/dev/null 2>&1 || record_fail 'prepare RESOLVED fixture transition'
      illegal_start="$REPORTS/illegal-resolved-start.md"
      cat >"$illegal_start" <<'EOF'
Repair round: 1
Executor: fixer
Agent ID: illegal-resolved-fixer
Repair hypothesis: Complete the repair before resolution.
EOF
      "$SCRIPT" "$ILLEGAL_PLAN" repair-start "$ILLEGAL_ID" "$illegal_start" >/dev/null 2>&1 || record_fail 'prepare RESOLVED fixture repair start'
      illegal_finish="$REPORTS/illegal-resolved-finish.md"
      cat >"$illegal_finish" <<EOF
Repair round: 1
Executor: fixer
Agent ID: illegal-resolved-fixer
Repair head: $(git -C "$REPO" rev-parse HEAD)
Replay status: VERIFIED
Replay evidence: $REPLAY
EOF
      "$SCRIPT" "$ILLEGAL_PLAN" repair-finish "$ILLEGAL_ID" "$illegal_finish" >/dev/null 2>&1 || record_fail 'prepare RESOLVED fixture repair finish'
      "$SCRIPT" "$ILLEGAL_PLAN" transition "$ILLEGAL_ID" RESOLVED "$illegal_finish" >/dev/null 2>&1 || record_fail 'prepare RESOLVED fixture resolution'
      ;;
    DEFERRED|DISMISSED|PARKED|BLOCKED)
      "$SCRIPT" "$ILLEGAL_PLAN" transition "$ILLEGAL_ID" "$illegal_state" "$REPORTS/illegal-$illegal_state.md" >/dev/null 2>&1 || record_fail "prepare $illegal_state fixture transition"
      ;;
  esac
}

illegal_index=30
for illegal_source in REPORTED REPAIRING RESOLVED DEFERRED DISMISSED PARKED BLOCKED; do
  prepare_illegal_state "$illegal_source" "$illegal_index"
  illegal_index=$((illegal_index + 1))
  for illegal_target in REPORTED REPAIRING RESOLVED DEFERRED DISMISSED PARKED BLOCKED; do
    is_legal_transition "$illegal_source" "$illegal_target" && continue
    case "$illegal_target" in
      REPORTED) illegal_evidence="$WAKE" ;;
      REPAIRING) illegal_evidence="$REPAIRING" ;;
      RESOLVED) illegal_evidence="$REPAIR_FINISH" ;;
      DEFERRED|DISMISSED|PARKED|BLOCKED) illegal_evidence="$REPORTS/illegal-$illegal_target.md" ;;
    esac
    before_hash=$(workspace_hash "$ILLEGAL_WORKSPACE")
    expect_failure "$illegal_source rejects illegal transition to $illegal_target" \
      "$SCRIPT" "$ILLEGAL_PLAN" transition "$ILLEGAL_ID" "$illegal_target" "$illegal_evidence"
    [ "$before_hash" = "$(workspace_hash "$ILLEGAL_WORKSPACE")" ] && record_pass "$illegal_source to $illegal_target leaves ledger and artifacts unchanged" || record_fail "$illegal_source to $illegal_target leaves ledger and artifacts unchanged"
  done
done

UNINITIALIZED_PLAN="$REPO/openspec/changes/uninitialized-read-only/plan.md"
mkdir -p "$(dirname "$UNINITIALIZED_PLAN")"
printf '%s\n' '# Uninitialized read-only fixture' >"$UNINITIALIZED_PLAN"
UNINITIALIZED_WORKSPACE="$REPO/.superpowers/gdd/uninitialized-read-only"
gdd_gitignore_hash=$(file_hash_or_absent "$REPO/.superpowers/gdd/.gitignore")
expect_failure 'guard rejects an uninitialized workspace without creating it' \
  "$SCRIPT" "$UNINITIALIZED_PLAN" guard 1 verifying-cleaner
[ ! -e "$UNINITIALIZED_WORKSPACE" ] && record_pass 'failed guard does not create its plan workspace' || record_fail 'failed guard does not create its plan workspace'
[ "$(file_hash_or_absent "$REPO/.superpowers/gdd/.gitignore")" = "$gdd_gitignore_hash" ] && record_pass 'failed guard does not rewrite the GDD gitignore' || record_fail 'failed guard does not rewrite the GDD gitignore'
expect_failure 'repair-entry rejects an uninitialized workspace without creating it' \
  "$SCRIPT" "$UNINITIALIZED_PLAN" repair-entry 1 GDD-F0001
[ ! -e "$UNINITIALIZED_WORKSPACE" ] && record_pass 'failed repair-entry does not create its plan workspace' || record_fail 'failed repair-entry does not create its plan workspace'
[ "$(file_hash_or_absent "$REPO/.superpowers/gdd/.gitignore")" = "$gdd_gitignore_hash" ] && record_pass 'failed repair-entry does not rewrite the GDD gitignore' || record_fail 'failed repair-entry does not rewrite the GDD gitignore'

GUARD_BLOCK_PLAN="$REPO/openspec/changes/guard-blocks/plan.md"
mkdir -p "$(dirname "$GUARD_BLOCK_PLAN")"
printf '%s\n' '# Guard blocking fixture' >"$GUARD_BLOCK_PLAN"
expect_success 'guard blocking fixture initializes' "$SCRIPT" "$GUARD_BLOCK_PLAN" init
GUARD_BLOCK_WORKSPACE="$REPO/.superpowers/gdd/guard-blocks"
guard_reported_id=$("$SCRIPT" "$GUARD_BLOCK_PLAN" report 60 'Security Reviewer' "$FULL_REPORT") || guard_reported_id=''
before_hash=$(workspace_hash "$GUARD_BLOCK_WORKSPACE")
expect_failure 'guard blocks a REPORTED finding' \
  "$SCRIPT" "$GUARD_BLOCK_PLAN" guard 60 verifying-cleaner
[ "$before_hash" = "$(workspace_hash "$GUARD_BLOCK_WORKSPACE")" ] && record_pass 'REPORTED guard rejection is read-only' || record_fail 'REPORTED guard rejection is read-only'
BLOCKED_RULING="$REPORTS/guard-blocked.md"
write_terminal_ruling "$BLOCKED_RULING" BLOCKED
expect_success 'guard blocking fixture reaches BLOCKED' \
  "$SCRIPT" "$GUARD_BLOCK_PLAN" transition "$guard_reported_id" BLOCKED "$BLOCKED_RULING"
before_hash=$(workspace_hash "$GUARD_BLOCK_WORKSPACE")
expect_failure 'guard blocks a BLOCKED finding' \
  "$SCRIPT" "$GUARD_BLOCK_PLAN" guard 60 verifying-cleaner
[ "$before_hash" = "$(workspace_hash "$GUARD_BLOCK_WORKSPACE")" ] && record_pass 'BLOCKED guard rejection is read-only' || record_fail 'BLOCKED guard rejection is read-only'

guard_slice=61
for replay_origin in Cleaner Architect 'Security Reviewer' Hardener QA; do
  case "$replay_origin" in
    Cleaner) replay_endpoint=verifying-cleaner; next_endpoint=verifying-architect ;;
    Architect) replay_endpoint=verifying-architect; next_endpoint=verifying-security ;;
    'Security Reviewer') replay_endpoint=verifying-security; next_endpoint=verifying-hardener ;;
    Hardener) replay_endpoint=verifying-hardener; next_endpoint=verifying-qa ;;
    QA) replay_endpoint=verifying-qa; next_endpoint=verified ;;
  esac
  guard_fixture="guard-${replay_origin// /-}"
  guard_plan="$REPO/openspec/changes/$guard_fixture/plan.md"
  guard_workspace="$REPO/.superpowers/gdd/$guard_fixture"
  guard_report="$REPORTS/$guard_fixture-report.md"
  guard_repairing="$REPORTS/$guard_fixture-repairing.md"
  mkdir -p "$(dirname "$guard_plan")"
  printf '%s\n' "# Guard endpoint fixture for $replay_origin" >"$guard_plan"
  write_report "$guard_report" "$replay_origin"
  expect_success "guard $replay_origin fixture initializes" "$SCRIPT" "$guard_plan" init
  guard_id=$("$SCRIPT" "$guard_plan" report "$guard_slice" "$replay_origin" "$guard_report") || guard_id=''
  write_repairing_evidence "$guard_repairing" "Replay through $replay_origin." "$(git -C "$REPO" rev-parse HEAD)" "$replay_origin"
  expect_success "$replay_origin finding enters REPAIRING" \
    "$SCRIPT" "$guard_plan" transition "$guard_id" REPAIRING "$guard_repairing"
  before_hash=$(workspace_hash "$guard_workspace")
  expect_success "$replay_origin permits its own replay endpoint" \
    "$SCRIPT" "$guard_plan" guard "$guard_slice" "$replay_endpoint" "$replay_origin"
  [ "$before_hash" = "$(workspace_hash "$guard_workspace")" ] && record_pass "$replay_origin successful guard is read-only" || record_fail "$replay_origin successful guard is read-only"
  expect_failure "$replay_origin blocks the next replay endpoint while REPAIRING" \
    "$SCRIPT" "$guard_plan" guard "$guard_slice" "$next_endpoint"
  GUARD_START="$REPORTS/$guard_fixture-start.md"
  GUARD_FINISH="$REPORTS/$guard_fixture-finish.md"
  write_repair_start "$GUARD_START" 1 fixer "guard-agent-$guard_slice" "Resolve the $replay_origin finding."
  expect_success "$replay_origin repair starts" "$SCRIPT" "$guard_plan" repair-start "$guard_id" "$GUARD_START"
  write_repair_finish "$GUARD_FINISH" 1 fixer "guard-agent-$guard_slice" "$(git -C "$REPO" rev-parse HEAD)" VERIFIED "$REPLAY"
  expect_success "$replay_origin repair finishes VERIFIED" "$SCRIPT" "$guard_plan" repair-finish "$guard_id" "$GUARD_FINISH"
  expect_success "$replay_origin finding resolves" "$SCRIPT" "$guard_plan" transition "$guard_id" RESOLVED "$GUARD_FINISH"
  expect_success "$replay_origin permits advancement after RESOLVED" \
    "$SCRIPT" "$guard_plan" guard "$guard_slice" verified "$replay_origin"
  guard_slice=$((guard_slice + 1))
done

REENTRY_PLAN="$REPO/openspec/changes/verified-reentry/plan.md"
mkdir -p "$(dirname "$REENTRY_PLAN")"
printf '%s\n' '# Verified re-entry fixture' >"$REENTRY_PLAN"
expect_success 'verified re-entry fixture initializes' "$SCRIPT" "$REENTRY_PLAN" init
REENTRY_WORKSPACE="$REPO/.superpowers/gdd/verified-reentry"
reentry_id=$("$SCRIPT" "$REENTRY_PLAN" report 70 'Security Reviewer' "$FULL_REPORT") || reentry_id=''
expect_success 'verified re-entry fixture records a terminal disposition' \
  "$SCRIPT" "$REENTRY_PLAN" transition "$reentry_id" DISMISSED "$TERMINAL_RULING"
expect_success 'verified re-entry fixture records Wake evidence' \
  "$SCRIPT" "$REENTRY_PLAN" transition "$reentry_id" REPORTED "$WAKE"
expect_success 'verified re-entry fixture returns to REPAIRING' \
  "$SCRIPT" "$REENTRY_PLAN" transition "$reentry_id" REPAIRING "$REPAIRING"
before_hash=$(workspace_hash "$REENTRY_WORKSPACE")
expect_success 'verified re-entry accepts terminal, wake, and repair history' \
  "$SCRIPT" "$REENTRY_PLAN" repair-entry 70 "$reentry_id" verified-reentry
[ "$before_hash" = "$(workspace_hash "$REENTRY_WORKSPACE")" ] && record_pass 'successful verified repair-entry is read-only' || record_fail 'successful verified repair-entry is read-only'
expect_failure 'slice repair-entry rejects a different requested slice' \
  "$SCRIPT" "$REENTRY_PLAN" repair-entry 71 "$reentry_id"

before_hash=$(workspace_hash "$WORKSPACE")
expect_failure 'feature repair-entry rejects a slice outside Affected slices' \
  "$SCRIPT" "$PLAN" repair-entry 3 "$feature_id"
[ "$before_hash" = "$(workspace_hash "$WORKSPACE")" ] && record_pass 'feature repair-entry rejection is read-only' || record_fail 'feature repair-entry rejection is read-only'

resolved_digest_id=$("$SCRIPT" "$DIGEST_PLAN" report 12 'Security Reviewer' "$FULL_REPORT") || resolved_digest_id=''
expect_success 'digest resolved fixture enters REPAIRING' \
  "$SCRIPT" "$DIGEST_PLAN" transition "$resolved_digest_id" REPAIRING "$REPAIRING"
DIGEST_RESOLVED_START="$REPORTS/digest-resolved-start.md"
DIGEST_RESOLVED_FINISH="$REPORTS/digest-resolved-finish.md"
write_repair_start "$DIGEST_RESOLVED_START" 1 fixer digest-resolved-agent 'Resolve a finding that must not appear in the digest.'
expect_success 'digest resolved fixture starts repair' \
  "$SCRIPT" "$DIGEST_PLAN" repair-start "$resolved_digest_id" "$DIGEST_RESOLVED_START"
write_repair_finish "$DIGEST_RESOLVED_FINISH" 1 fixer digest-resolved-agent "$(git -C "$REPO" rev-parse HEAD)" VERIFIED "$REPLAY"
expect_success 'digest resolved fixture finishes repair' \
  "$SCRIPT" "$DIGEST_PLAN" repair-finish "$resolved_digest_id" "$DIGEST_RESOLVED_FINISH"
expect_success 'digest resolved fixture reaches RESOLVED' \
  "$SCRIPT" "$DIGEST_PLAN" transition "$resolved_digest_id" RESOLVED "$DIGEST_RESOLVED_FINISH"
expect_success 'digest rewrites after a RESOLVED finding' \
  "$SCRIPT" "$DIGEST_PLAN" digest "$DIGEST_WORKSPACE/findings.md"
[ "$(grep -Fc '`GDD-F0001`' "$DIGEST_WORKSPACE/findings.md")" -eq 1 ] && record_pass 'digest includes DEFERRED exactly once' || record_fail 'digest includes DEFERRED exactly once'
[ "$(grep -Fc '`GDD-F0002`' "$DIGEST_WORKSPACE/findings.md")" -eq 1 ] && record_pass 'digest includes DISMISSED exactly once' || record_fail 'digest includes DISMISSED exactly once'
[ "$(grep -Fc '`GDD-F0003`' "$DIGEST_WORKSPACE/findings.md")" -eq 1 ] && record_pass 'digest includes PARKED exactly once' || record_fail 'digest includes PARKED exactly once'
if grep -Fq "\`$resolved_digest_id\`" "$DIGEST_WORKSPACE/findings.md"; then
  record_fail 'digest excludes RESOLVED findings'
else
  record_pass 'digest excludes RESOLVED findings'
fi

for blocking_digest_state in REPORTED REPAIRING BLOCKED; do
  blocking_digest_fixture="digest-block-$blocking_digest_state"
  blocking_digest_plan="$REPO/openspec/changes/$blocking_digest_fixture/plan.md"
  blocking_digest_workspace="$REPO/.superpowers/gdd/$blocking_digest_fixture"
  mkdir -p "$(dirname "$blocking_digest_plan")"
  printf '%s\n' "# Digest blocking fixture for $blocking_digest_state" >"$blocking_digest_plan"
  expect_success "digest $blocking_digest_state fixture initializes" "$SCRIPT" "$blocking_digest_plan" init
  blocking_digest_id=$("$SCRIPT" "$blocking_digest_plan" report 80 'Security Reviewer' "$FULL_REPORT") || blocking_digest_id=''
  case "$blocking_digest_state" in
    REPORTED) ;;
    REPAIRING) "$SCRIPT" "$blocking_digest_plan" transition "$blocking_digest_id" REPAIRING "$REPAIRING" >/dev/null 2>&1 || record_fail 'prepare REPAIRING digest blocker' ;;
    BLOCKED) "$SCRIPT" "$blocking_digest_plan" transition "$blocking_digest_id" BLOCKED "$BLOCKED_RULING" >/dev/null 2>&1 || record_fail 'prepare BLOCKED digest blocker' ;;
  esac
  before_hash=$(workspace_hash "$blocking_digest_workspace")
  expect_failure "digest fails while a finding is $blocking_digest_state" \
    "$SCRIPT" "$blocking_digest_plan" digest "$blocking_digest_workspace/findings.md"
  [ "$before_hash" = "$(workspace_hash "$blocking_digest_workspace")" ] && record_pass "digest $blocking_digest_state failure leaves workspace unchanged" || record_fail "digest $blocking_digest_state failure leaves workspace unchanged"
done

FINISH_MATRIX_PLAN="$REPO/openspec/changes/repair-finish-matrix/plan.md"
mkdir -p "$(dirname "$FINISH_MATRIX_PLAN")"
printf '%s\n' '# Repair finish matrix fixture' >"$FINISH_MATRIX_PLAN"
expect_success 'repair-finish matrix fixture initializes' "$SCRIPT" "$FINISH_MATRIX_PLAN" init
FINISH_MATRIX_WORKSPACE="$REPO/.superpowers/gdd/repair-finish-matrix"
finish_matrix_id=$("$SCRIPT" "$FINISH_MATRIX_PLAN" report 90 'Security Reviewer' "$FULL_REPORT") || finish_matrix_id=''
expect_success 'repair-finish matrix finding enters REPAIRING' \
  "$SCRIPT" "$FINISH_MATRIX_PLAN" transition "$finish_matrix_id" REPAIRING "$REPAIRING"
FINISH_MATRIX_START="$REPORTS/finish-matrix-start.md"
FINISH_MATRIX_EVIDENCE="$REPORTS/finish-matrix-evidence.md"
write_repair_start "$FINISH_MATRIX_START" 1 fixer finish-matrix-agent 'Validate every repair-finish field.'
expect_success 'repair-finish matrix starts round 1' \
  "$SCRIPT" "$FINISH_MATRIX_PLAN" repair-start "$finish_matrix_id" "$FINISH_MATRIX_START"
finish_matrix_head=$(git -C "$REPO" rev-parse HEAD)
finish_matrix_tree=$(git -C "$REPO" rev-parse 'HEAD^{tree}')
unrelated_finish_head=$(printf '%s\n' 'unrelated repair head' | git -C "$REPO" commit-tree "$finish_matrix_tree")

for finish_error in wrong-round wrong-executor wrong-agent missing-head unknown-head unrelated-head invalid-status missing-replay empty-replay; do
  case "$finish_error" in
    wrong-round) write_repair_finish "$FINISH_MATRIX_EVIDENCE" 2 fixer finish-matrix-agent "$finish_matrix_head" FAILED "$REPLAY" ;;
    wrong-executor) write_repair_finish "$FINISH_MATRIX_EVIDENCE" 1 fixer-max finish-matrix-agent "$finish_matrix_head" FAILED "$REPLAY" ;;
    wrong-agent) write_repair_finish "$FINISH_MATRIX_EVIDENCE" 1 fixer another-agent "$finish_matrix_head" FAILED "$REPLAY" ;;
    missing-head) write_repair_finish "$FINISH_MATRIX_EVIDENCE" 1 fixer finish-matrix-agent '' FAILED "$REPLAY" ;;
    unknown-head) write_repair_finish "$FINISH_MATRIX_EVIDENCE" 1 fixer finish-matrix-agent deadbeef FAILED "$REPLAY" ;;
    unrelated-head) write_repair_finish "$FINISH_MATRIX_EVIDENCE" 1 fixer finish-matrix-agent "$unrelated_finish_head" FAILED "$REPLAY" ;;
    invalid-status) write_repair_finish "$FINISH_MATRIX_EVIDENCE" 1 fixer finish-matrix-agent "$finish_matrix_head" PASSED "$REPLAY" ;;
    missing-replay) write_repair_finish "$FINISH_MATRIX_EVIDENCE" 1 fixer finish-matrix-agent "$finish_matrix_head" FAILED "$REPORTS/missing-replay.md" ;;
    empty-replay) empty_replay="$REPORTS/empty-replay.md"; : >"$empty_replay"; write_repair_finish "$FINISH_MATRIX_EVIDENCE" 1 fixer finish-matrix-agent "$finish_matrix_head" FAILED "$empty_replay" ;;
  esac
  before_hash=$(workspace_hash "$FINISH_MATRIX_WORKSPACE")
  expect_failure "repair-finish rejects $finish_error evidence" \
    "$SCRIPT" "$FINISH_MATRIX_PLAN" repair-finish "$finish_matrix_id" "$FINISH_MATRIX_EVIDENCE"
  [ "$before_hash" = "$(workspace_hash "$FINISH_MATRIX_WORKSPACE")" ] && record_pass "invalid repair-finish $finish_error leaves workspace unchanged" || record_fail "invalid repair-finish $finish_error leaves workspace unchanged"
done
write_repair_finish "$FINISH_MATRIX_EVIDENCE" 1 fixer finish-matrix-agent "$finish_matrix_head" FAILED "$REPLAY"
expect_success 'repair-finish accepts matching FAILED evidence' \
  "$SCRIPT" "$FINISH_MATRIX_PLAN" repair-finish "$finish_matrix_id" "$FINISH_MATRIX_EVIDENCE"
before_hash=$(workspace_hash "$FINISH_MATRIX_WORKSPACE")
expect_failure 'RESOLVED rejects a latest FAILED repair replay' \
  "$SCRIPT" "$FINISH_MATRIX_PLAN" transition "$finish_matrix_id" RESOLVED "$FINISH_MATRIX_EVIDENCE"
[ "$before_hash" = "$(workspace_hash "$FINISH_MATRIX_WORKSPACE")" ] && record_pass 'failed RESOLVED transition leaves workspace unchanged' || record_fail 'failed RESOLVED transition leaves workspace unchanged'

MISSING_DIGEST_PLAN="$REPO/openspec/changes/missing-digest-material/plan.md"
mkdir -p "$(dirname "$MISSING_DIGEST_PLAN")"
printf '%s\n' '# Missing digest material fixture' >"$MISSING_DIGEST_PLAN"
expect_success 'missing digest fixture initializes' "$SCRIPT" "$MISSING_DIGEST_PLAN" init
MISSING_DIGEST_WORKSPACE="$REPO/.superpowers/gdd/missing-digest-material"
missing_digest_id=$("$SCRIPT" "$MISSING_DIGEST_PLAN" report 91 'Security Reviewer' "$FULL_REPORT") || missing_digest_id=''
expect_success 'missing digest fixture records a terminal finding' \
  "$SCRIPT" "$MISSING_DIGEST_PLAN" transition "$missing_digest_id" DISMISSED "$TERMINAL_RULING"
missing_digest_ledger_hash=$(file_hash_or_absent "$MISSING_DIGEST_WORKSPACE/findings.tsv")
expect_fault 'digest stops with fully staged output' before-artifact-publication \
  "$SCRIPT" "$MISSING_DIGEST_PLAN" digest "$MISSING_DIGEST_WORKSPACE/findings.md"
missing_staged_output=$(sed -n $'s/^staged_output\t//p' "$MISSING_DIGEST_WORKSPACE/.finding-journal")
rm "$missing_staged_output"
expect_failure 'digest recovery fails closed when staged output is missing' \
  "$SCRIPT" "$MISSING_DIGEST_PLAN" init
[ "$(file_hash_or_absent "$MISSING_DIGEST_WORKSPACE/findings.tsv")" = "$missing_digest_ledger_hash" ] && record_pass 'missing digest material leaves the last complete ledger unchanged' || record_fail 'missing digest material leaves the last complete ledger unchanged'
[ ! -e "$MISSING_DIGEST_WORKSPACE/findings.md" ] && record_pass 'missing digest material exposes no partial output' || record_fail 'missing digest material exposes no partial output'
[ -f "$MISSING_DIGEST_WORKSPACE/.finding-journal" ] && record_pass 'missing digest material keeps the recovery journal' || record_fail 'missing digest material keeps the recovery journal'

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
