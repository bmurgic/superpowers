#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/gdd-slice-state"
FINDING_STATE="$SCRIPT_DIR/gdd-finding-state"
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

file_hash_or_absent() {
  if [ -f "$1" ]; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    printf 'absent\n'
  fi
}

fixture_hash() {
  plan_file=$1
  workspace_name=$(basename "$(dirname "$plan_file")")
  workspace="$REPO/.superpowers/gdd/$workspace_name"
  {
    file_hash_or_absent "$(dirname "$plan_file")/tasks.md"
    file_hash_or_absent "$workspace/ledger.tsv"
    find "$workspace" -type f -print0 | sort -z | xargs -0 shasum -a 256
    file_hash_or_absent "$REPO/.superpowers/gdd/.gitignore"
  } | shasum -a 256 | awk '{ print $1 }'
}

expect_failure_unchanged() {
  name=$1
  plan_file=$2
  shift 2
  before_hash=$(fixture_hash "$plan_file")
  expect_failure "$name" "$@"
  after_hash=$(fixture_hash "$plan_file")
  if [ "$before_hash" = "$after_hash" ]; then
    record_pass "$name leaves tasks, ledgers, findings, and gitignore unchanged"
  else
    record_fail "$name leaves tasks, ledgers, findings, and gitignore unchanged"
  fi
}

write_finding_report() {
  report_file=$1
  origin=$2
  cat >"$report_file" <<EOF
Origin role: $origin
Severity claim: Important
Blocking claim: yes
Observed failure: The recorded replay sequence is incomplete.
Evidence: reports/review.md
Violated authority: approved design
Assumptions: The slice state must reflect adjudicated findings.
Failure scenario: A stale verification sequence accepts an unresolved finding.
Proposed repair: Replay the affected lifecycle boundary.
Repair effects: Replays the required verification roles.
EOF
}

write_terminal_ruling() {
  ruling_file=$1
  disposition=$2
  cat >"$ruling_file" <<EOF
Disposition: $disposition
Ruling: The recorded finding does not require an immediate repair.
Cost if wrong: A later lifecycle transition could rely on an incomplete review.
Wake condition: New evidence shows the lifecycle boundary is unsafe.
Fable result: UNAVAILABLE: Advisor is unavailable for this deterministic fixture.
EOF
}

write_repairing_evidence() {
  evidence_file=$1
  endpoint=$2
  affected_slices=${3:-}
  {
    printf '%s\n' 'Repair hypothesis: Replay the lifecycle from the finding endpoint.'
    printf 'Repair base: %s\n' "$(git -C "$REPO" rev-parse HEAD)"
    printf 'Replay through: %s\n' "$endpoint"
    [ -z "$affected_slices" ] || printf 'Affected slices: %s\n' "$affected_slices"
  } >"$evidence_file"
}

write_repair_start() {
  repair_file=$1
  agent_id=$2
  cat >"$repair_file" <<EOF
Repair round: 1
Executor: fixer
Agent ID: $agent_id
Repair hypothesis: Replay the lifecycle from the finding endpoint.
EOF
}

write_repair_finish() {
  repair_file=$1
  agent_id=$2
  replay_evidence=$3
  cat >"$repair_file" <<EOF
Repair round: 1
Executor: fixer
Agent ID: $agent_id
Repair head: $(git -C "$REPO" rev-parse HEAD)
Replay status: VERIFIED
Replay evidence: $replay_evidence
EOF
}

create_fixture() {
  fixture_name=$1
  fixture_dir="$REPO/openspec/changes/$fixture_name"
  FIXTURE_PLAN="$fixture_dir/plan.md"
  FIXTURE_TASKS="$fixture_dir/tasks.md"
  mkdir -p "$fixture_dir"
  printf '%s\n' "# $fixture_name plan" >"$FIXTURE_PLAN"
  printf '%s\n' \
    '## 1. First lifecycle boundary' \
    '**Slice state:** [ ] QUEUED' \
    '' \
    '- [ ] 1.1 Implement the first boundary' \
    '- [ ] 1.V **Slice verification gate**' \
    '' \
    '## 2. Second lifecycle boundary' \
    '**Slice state:** [ ] QUEUED' \
    '' \
    '- [ ] 2.1 Implement the second boundary' \
    '- [ ] 2.V **Slice verification gate**' \
    '' \
    '## 3. Unlisted lifecycle boundary' \
    '**Slice state:** [ ] QUEUED' \
    '' \
    '- [ ] 3.1 Implement the unlisted boundary' \
    '- [ ] 3.V **Slice verification gate**' >"$FIXTURE_TASKS"
  expect_success "$fixture_name finding workspace initializes" \
    "$FINDING_STATE" "$FIXTURE_PLAN" init
}

advance_to_security() {
  plan_file=$1
  slice_number=$2
  expect_success "slice $slice_number enters implementing" \
    "$SCRIPT" "$plan_file" "$slice_number" implementing
  expect_success "slice $slice_number reaches Cleaner" \
    "$SCRIPT" "$plan_file" "$slice_number" verifying-cleaner "$IMPLEMENTER_REPORT"
  expect_success "slice $slice_number reaches Architect" \
    "$SCRIPT" "$plan_file" "$slice_number" verifying-architect "$CLEANER_REPORT"
  expect_success "slice $slice_number reaches Security" \
    "$SCRIPT" "$plan_file" "$slice_number" verifying-security "$ARCHITECT_REPORT"
}

advance_to_verified() {
  plan_file=$1
  slice_number=$2
  advance_to_security "$plan_file" "$slice_number"
  expect_success "slice $slice_number reaches Hardener" \
    "$SCRIPT" "$plan_file" "$slice_number" verifying-hardener "$SECURITY_REPORT"
  expect_success "slice $slice_number reaches QA" \
    "$SCRIPT" "$plan_file" "$slice_number" verifying-qa "$HARDENER_REPORT"
  expect_success "slice $slice_number reaches VERIFIED" \
    "$SCRIPT" "$plan_file" "$slice_number" verified "$QA_REPORT" "$SUITE_REPORT"
}

resolve_finding() {
  plan_file=$1
  finding_id=$2
  agent_id=$3
  write_repair_start "$REPAIR_START" "$agent_id"
  expect_success "$agent_id starts the replay repair" \
    "$FINDING_STATE" "$plan_file" repair-start "$finding_id" "$REPAIR_START"
  write_repair_finish "$REPAIR_FINISH" "$agent_id" "$REPLAY_EVIDENCE"
  expect_success "$agent_id finishes the replay repair" \
    "$FINDING_STATE" "$plan_file" repair-finish "$finding_id" "$REPAIR_FINISH"
  expect_success "$agent_id resolves the replay finding" \
    "$FINDING_STATE" "$plan_file" transition "$finding_id" RESOLVED "$REPAIR_FINISH"
}

REPO="$TEST_ROOT/repo"
CHANGE="$REPO/openspec/changes/reset-password"
PLAN="$CHANGE/plan.md"
TASKS="$CHANGE/tasks.md"
mkdir -p "$CHANGE"
git -C "$REPO" init -q
git -C "$REPO" config user.name 'Test Bot'
git -C "$REPO" config user.email 'test@example.com'

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
printf '%s\n' 'fixture' >"$REPO/README.md"
git -C "$REPO" add README.md openspec
git -C "$REPO" commit -qm 'chore: slice-state fixture'

IMPLEMENTER_REPORT="$TEST_ROOT/implementer.md"
CLEANER_REPORT="$TEST_ROOT/cleaner.md"
ARCHITECT_REPORT="$TEST_ROOT/architect.md"
SECURITY_REPORT="$TEST_ROOT/security.md"
HARDENER_REPORT="$TEST_ROOT/hardener.md"
QA_REPORT="$TEST_ROOT/qa.md"
SUITE_REPORT="$TEST_ROOT/suite.md"
FINDING_REPORT="$TEST_ROOT/finding.md"
FIXER_REPORT="$TEST_ROOT/fixer.md"
FINDING_DETAILS="$TEST_ROOT/finding-details.md"
TERMINAL_RULING="$TEST_ROOT/terminal.md"
REPAIRING_EVIDENCE="$TEST_ROOT/repairing.md"
REPAIR_START="$TEST_ROOT/repair-start.md"
REPAIR_FINISH="$TEST_ROOT/repair-finish.md"
REPLAY_EVIDENCE="$TEST_ROOT/replay.md"
WAKE_EVIDENCE="$TEST_ROOT/wake.md"

printf '%s\n' 'Status: IMPLEMENTED' >"$IMPLEMENTER_REPORT"
printf '%s\n' 'Status: COMPLETE' >"$CLEANER_REPORT"
printf '%s\n' 'Status: COMPLETE' >"$ARCHITECT_REPORT"
printf '%s\n' 'Status: CLEAN' >"$SECURITY_REPORT"
printf '%s\n' 'Status: VERIFIED' >"$HARDENER_REPORT"
printf '%s\n' 'Status: VERIFIED' >"$QA_REPORT"
printf '%s\n' 'Status: PASS' >"$SUITE_REPORT"
printf '%s\n' 'Status: FINDINGS' >"$FINDING_REPORT"
printf '%s\n' 'Status: FIXED' >"$FIXER_REPORT"
write_finding_report "$FINDING_DETAILS" 'Security Reviewer'
write_terminal_ruling "$TERMINAL_RULING" DISMISSED
write_repairing_evidence "$REPAIRING_EVIDENCE" 'Security Reviewer'
printf '%s\n' 'Replay completed.' >"$REPLAY_EVIDENCE"
printf '%s\n' 'Wake evidence: a final review found fresh lifecycle evidence.' >"$WAKE_EVIDENCE"

expect_success 'finding workspace initializes' \
  "$FINDING_STATE" "$PLAN" init

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

expect_failure_unchanged 'Security FINDINGS without a recorded Security Reviewer finding fails' "$PLAN" \
  "$SCRIPT" "$PLAN" 1 verifying-hardener "$FINDING_REPORT"
security_id=$("$FINDING_STATE" "$PLAN" report 1 'Security Reviewer' "$FINDING_DETAILS")
expect_failure_unchanged 'a REPORTED Security finding blocks Hardener' "$PLAN" \
  "$SCRIPT" "$PLAN" 1 verifying-hardener "$FINDING_REPORT"
expect_success 'a complete DISMISSED Security finding admits Hardener with Status: FINDINGS' \
  "$FINDING_STATE" "$PLAN" transition "$security_id" DISMISSED "$TERMINAL_RULING"
expect_success 'dismissed Security finding admits Hardener' \
  "$SCRIPT" "$PLAN" 1 verifying-hardener "$FINDING_REPORT"
expect_success 'clean Security verdict admits Hardener' \
  "$SCRIPT" "$PLAN" 1 verifying-hardener "$SECURITY_REPORT"

repair_id=$("$FINDING_STATE" "$PLAN" report 1 'Security Reviewer' "$FINDING_DETAILS")
expect_success 'Security repair finding enters REPAIRING' \
  "$FINDING_STATE" "$PLAN" transition "$repair_id" REPAIRING "$REPAIRING_EVIDENCE"
expect_success 'a REPAIRING Security finding permits verifying-cleaner after repair entry' \
  "$SCRIPT" "$PLAN" 1 repairing "$FIXER_REPORT" "$repair_id"
expect_file_contains 'repair state is visible' \
  "$TASKS" '**Slice state:** [~] REPAIRING'
expect_failure_unchanged 'repair cannot skip Cleaner replay' "$PLAN" \
  "$SCRIPT" "$PLAN" 1 verifying-architect "$FIXER_REPORT"
expect_success 'fixer evidence restarts at Cleaner' \
  "$SCRIPT" "$PLAN" 1 verifying-cleaner "$FIXER_REPORT"
expect_success 'Cleaner replay admits Architect' \
  "$SCRIPT" "$PLAN" 1 verifying-architect "$CLEANER_REPORT"
expect_success 'Architect replay admits Security' \
  "$SCRIPT" "$PLAN" 1 verifying-security "$ARCHITECT_REPORT"
expect_failure_unchanged 'the same Security finding blocks verifying-hardener at its recorded endpoint' "$PLAN" \
  "$SCRIPT" "$PLAN" 1 verifying-hardener "$SECURITY_REPORT"
write_repair_start "$REPAIR_START" 'slice-repair-agent'
expect_success 'Security replay repair starts' \
  "$FINDING_STATE" "$PLAN" repair-start "$repair_id" "$REPAIR_START"
git -C "$REPO" commit --allow-empty -qm 'fix: slice repair fixture'
write_repair_finish "$REPAIR_FINISH" 'slice-repair-agent' "$REPLAY_EVIDENCE"
expect_success 'Security replay repair finishes' \
  "$FINDING_STATE" "$PLAN" repair-finish "$repair_id" "$REPAIR_FINISH"
expect_success 'RESOLVED replay evidence permits verifying-hardener' \
  "$FINDING_STATE" "$PLAN" transition "$repair_id" RESOLVED "$REPAIR_FINISH"
expect_success 'resolved Security finding admits Hardener' \
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

create_fixture 'security-parked'
parked_plan=$FIXTURE_PLAN
advance_to_security "$parked_plan" 1
parked_id=$("$FINDING_STATE" "$parked_plan" report 1 'Security Reviewer' "$FINDING_DETAILS")
write_terminal_ruling "$TERMINAL_RULING" PARKED
expect_success 'a PARKED Security finding records advisor unavailability' \
  "$FINDING_STATE" "$parked_plan" transition "$parked_id" PARKED "$TERMINAL_RULING"
expect_success 'a PARKED Security finding with advisor unavailable admits Hardener' \
  "$SCRIPT" "$parked_plan" 1 verifying-hardener "$FINDING_REPORT"

create_fixture 'security-blocked'
blocked_plan=$FIXTURE_PLAN
advance_to_security "$blocked_plan" 1
blocked_id=$("$FINDING_STATE" "$blocked_plan" report 1 'Security Reviewer' "$FINDING_DETAILS")
write_terminal_ruling "$TERMINAL_RULING" BLOCKED
expect_success 'a Security finding enters BLOCKED' \
  "$FINDING_STATE" "$blocked_plan" transition "$blocked_id" BLOCKED "$TERMINAL_RULING"
expect_failure_unchanged 'a BLOCKED Security finding blocks Hardener' "$blocked_plan" \
  "$SCRIPT" "$blocked_plan" 1 verifying-hardener "$FINDING_REPORT"

endpoint_slice=10
for replay_origin in Cleaner Architect 'Security Reviewer' Hardener QA; do
  endpoint_name="endpoint-${replay_origin// /-}"
  create_fixture "$endpoint_name"
  endpoint_plan=$FIXTURE_PLAN
  advance_to_security "$endpoint_plan" 1
  endpoint_report="$TEST_ROOT/$endpoint_name-report.md"
  endpoint_repairing="$TEST_ROOT/$endpoint_name-repairing.md"
  write_finding_report "$endpoint_report" "$replay_origin"
  write_repairing_evidence "$endpoint_repairing" "$replay_origin"
  endpoint_id=$("$FINDING_STATE" "$endpoint_plan" report 1 "$replay_origin" "$endpoint_report")
  expect_success "$replay_origin endpoint finding enters REPAIRING" \
    "$FINDING_STATE" "$endpoint_plan" transition "$endpoint_id" REPAIRING "$endpoint_repairing"
  expect_success "$replay_origin finding opens the slice repair replay" \
    "$SCRIPT" "$endpoint_plan" 1 repairing "$FIXER_REPORT" "$endpoint_id"
  case "$replay_origin" in
    Cleaner) replay_steps='verifying-cleaner'; next_step='verifying-architect' ;;
    Architect) replay_steps='verifying-cleaner verifying-architect'; next_step='verifying-security' ;;
    'Security Reviewer') replay_steps='verifying-cleaner verifying-architect verifying-security'; next_step='verifying-hardener' ;;
    Hardener) replay_steps='verifying-cleaner verifying-architect verifying-security verifying-hardener'; next_step='verifying-qa' ;;
    QA) replay_steps='verifying-cleaner verifying-architect verifying-security verifying-hardener verifying-qa'; next_step='verified' ;;
  esac
  for replay_step in $replay_steps; do
    case "$replay_step" in
      verifying-cleaner) replay_report=$FIXER_REPORT ;;
      verifying-architect) replay_report=$CLEANER_REPORT ;;
      verifying-security) replay_report=$ARCHITECT_REPORT ;;
      verifying-hardener) replay_report=$SECURITY_REPORT ;;
      verifying-qa) replay_report=$HARDENER_REPORT ;;
    esac
    expect_success "$replay_origin permits $replay_step through its endpoint" \
      "$SCRIPT" "$endpoint_plan" 1 "$replay_step" "$replay_report"
  done
  if [ "$next_step" = verified ]; then
    expect_failure_unchanged "$replay_origin blocks verified beyond its endpoint" "$endpoint_plan" \
      "$SCRIPT" "$endpoint_plan" 1 verified "$QA_REPORT" "$SUITE_REPORT"
  else
    case "$next_step" in
      verifying-architect) next_report=$CLEANER_REPORT ;;
      verifying-security) next_report=$ARCHITECT_REPORT ;;
      verifying-hardener) next_report=$SECURITY_REPORT ;;
      verifying-qa) next_report=$HARDENER_REPORT ;;
    esac
    expect_failure_unchanged "$replay_origin blocks $next_step beyond its endpoint" "$endpoint_plan" \
      "$SCRIPT" "$endpoint_plan" 1 "$next_step" "$next_report"
  fi
  resolve_finding "$endpoint_plan" "$endpoint_id" "endpoint-agent-$endpoint_slice"
  endpoint_slice=$((endpoint_slice + 1))
  if [ "$next_step" = verified ]; then
    expect_success "$replay_origin permits verified after RESOLVED" \
      "$SCRIPT" "$endpoint_plan" 1 verified "$QA_REPORT" "$SUITE_REPORT"
  else
    expect_success "$replay_origin permits $next_step after RESOLVED" \
      "$SCRIPT" "$endpoint_plan" 1 "$next_step" "$next_report"
  fi
done

create_fixture 'verified-reentry'
reentry_plan=$FIXTURE_PLAN
reentry_tasks=$FIXTURE_TASKS
advance_to_verified "$reentry_plan" 1
advance_to_verified "$reentry_plan" 2
advance_to_verified "$reentry_plan" 3

expect_failure_unchanged 'repairing a VERIFIED slice without a finding ID fails without writes' "$reentry_plan" \
  "$SCRIPT" "$reentry_plan" 1 repairing "$FIXER_REPORT"

nonmatching_id=$("$FINDING_STATE" "$reentry_plan" report 2 'Security Reviewer' "$FINDING_DETAILS")
expect_success 'nonmatching slice finding enters REPAIRING' \
  "$FINDING_STATE" "$reentry_plan" transition "$nonmatching_id" REPAIRING "$REPAIRING_EVIDENCE"
expect_failure_unchanged 'a nonmatching slice-scoped finding cannot reopen a VERIFIED slice' "$reentry_plan" \
  "$SCRIPT" "$reentry_plan" 1 repairing "$FIXER_REPORT" "$nonmatching_id"

direct_id=$("$FINDING_STATE" "$reentry_plan" report 1 'Security Reviewer' "$FINDING_DETAILS")
expect_success 'a newly reported slice finding moves to REPAIRING' \
  "$FINDING_STATE" "$reentry_plan" transition "$direct_id" REPAIRING "$REPAIRING_EVIDENCE"
expect_failure_unchanged 'a newly reported slice finding moved directly to REPAIRING cannot reopen a VERIFIED slice' "$reentry_plan" \
  "$SCRIPT" "$reentry_plan" 1 repairing "$FIXER_REPORT" "$direct_id"
write_terminal_ruling "$TERMINAL_RULING" DISMISSED
expect_success 'the direct re-entry fixture is dismissed before the woken replay' \
  "$FINDING_STATE" "$reentry_plan" transition "$direct_id" DISMISSED "$TERMINAL_RULING"

woken_id=$("$FINDING_STATE" "$reentry_plan" report 1 'Security Reviewer' "$FINDING_DETAILS")
woken_repairing="$TEST_ROOT/woken-repairing.md"
write_repairing_evidence "$woken_repairing" QA
write_terminal_ruling "$TERMINAL_RULING" DISMISSED
expect_success 'woken fixture receives a terminal disposition' \
  "$FINDING_STATE" "$reentry_plan" transition "$woken_id" DISMISSED "$TERMINAL_RULING"
expect_success 'woken fixture records immutable Wake evidence' \
  "$FINDING_STATE" "$reentry_plan" transition "$woken_id" REPORTED "$WAKE_EVIDENCE"
expect_success 'woken fixture enters REPAIRING' \
  "$FINDING_STATE" "$reentry_plan" transition "$woken_id" REPAIRING "$woken_repairing"
expect_success 'a matching woken slice-scoped finding reopens its VERIFIED slice' \
  "$SCRIPT" "$reentry_plan" 1 repairing "$FIXER_REPORT" "$woken_id"
expect_file_contains 'woken slice reopens its verification gate exactly once' \
  "$reentry_tasks" '- [ ] 1.V **Slice verification gate**'
reentry_ledger="$REPO/.superpowers/gdd/verified-reentry/ledger.tsv"
reentry_rows_before=$(awk -F '\t' '$1 == 1 && $2 == "REPAIRING" { count++ } END { print count + 0 }' "$reentry_ledger")
expect_success 'repeating the same valid repair entry is idempotent' \
  "$SCRIPT" "$reentry_plan" 1 repairing "$FIXER_REPORT" "$woken_id"
reentry_rows_after=$(awk -F '\t' '$1 == 1 && $2 == "REPAIRING" { count++ } END { print count + 0 }' "$reentry_ledger")
[ "$reentry_rows_before" = "$reentry_rows_after" ] && record_pass 'reopened verification gate receives exactly one repair transition' || record_fail 'reopened verification gate receives exactly one repair transition'
expect_failure_unchanged 'the reopened slice cannot verify with its stale QA, suite, or lifecycle sequence' "$reentry_plan" \
  "$SCRIPT" "$reentry_plan" 1 verified "$QA_REPORT" "$SUITE_REPORT"
expect_success 'fresh Cleaner evidence starts reopened replay' \
  "$SCRIPT" "$reentry_plan" 1 verifying-cleaner "$FIXER_REPORT"
expect_success 'fresh Architect evidence advances reopened replay' \
  "$SCRIPT" "$reentry_plan" 1 verifying-architect "$CLEANER_REPORT"
expect_success 'fresh Security evidence advances reopened replay' \
  "$SCRIPT" "$reentry_plan" 1 verifying-security "$ARCHITECT_REPORT"
expect_success 'fresh Hardener evidence advances reopened replay' \
  "$SCRIPT" "$reentry_plan" 1 verifying-hardener "$SECURITY_REPORT"
expect_success 'fresh QA evidence advances reopened replay' \
  "$SCRIPT" "$reentry_plan" 1 verifying-qa "$HARDENER_REPORT"
resolve_finding "$reentry_plan" "$woken_id" 'woken-repair-agent'
expect_success 'fresh Cleaner through QA evidence and a fresh final suite reverify the slice' \
  "$SCRIPT" "$reentry_plan" 1 verified "$QA_REPORT" "$SUITE_REPORT"

for affected_case in missing malformed duplicate; do
  invalid_feature_report="$TEST_ROOT/feature-$affected_case-report.md"
  invalid_feature_repairing="$TEST_ROOT/feature-$affected_case-repairing.md"
  write_finding_report "$invalid_feature_report" 'Branch Reviewer'
  case "$affected_case" in
    missing) affected_value='' ;;
    malformed) affected_value='first' ;;
    duplicate) affected_value='1,1' ;;
  esac
  write_repairing_evidence "$invalid_feature_repairing" QA "$affected_value"
  invalid_feature_id=$("$FINDING_STATE" "$reentry_plan" report feature 'Branch Reviewer' "$invalid_feature_report")
  expect_failure_unchanged "a feature-scoped Branch Reviewer finding rejects $affected_case Affected slices without writes" "$reentry_plan" \
    "$FINDING_STATE" "$reentry_plan" transition "$invalid_feature_id" REPAIRING "$invalid_feature_repairing"
done

nonmatching_feature_report="$TEST_ROOT/feature-nonmatching-report.md"
nonmatching_feature_repairing="$TEST_ROOT/feature-nonmatching-repairing.md"
write_finding_report "$nonmatching_feature_report" 'Branch Reviewer'
write_repairing_evidence "$nonmatching_feature_repairing" QA '3'
nonmatching_feature_id=$("$FINDING_STATE" "$reentry_plan" report feature 'Branch Reviewer' "$nonmatching_feature_report")
expect_success 'a feature-scoped finding with a nonmatching slice list enters REPAIRING' \
  "$FINDING_STATE" "$reentry_plan" transition "$nonmatching_feature_id" REPAIRING "$nonmatching_feature_repairing"
expect_failure_unchanged 'a feature-scoped Branch Reviewer finding rejects nonmatching Affected slices without writes' "$reentry_plan" \
  "$SCRIPT" "$reentry_plan" 1 repairing "$FIXER_REPORT" "$nonmatching_feature_id"

feature_report="$TEST_ROOT/feature-report.md"
feature_repairing="$TEST_ROOT/feature-repairing.md"
write_finding_report "$feature_report" 'Branch Reviewer'
write_repairing_evidence "$feature_repairing" QA '1,2'
feature_id=$("$FINDING_STATE" "$reentry_plan" report feature 'Branch Reviewer' "$feature_report")
expect_success 'a valid feature finding enters REPAIRING with matching Affected slices' \
  "$FINDING_STATE" "$reentry_plan" transition "$feature_id" REPAIRING "$feature_repairing"
expect_success 'a valid feature finding reopens the first listed VERIFIED slice' \
  "$SCRIPT" "$reentry_plan" 1 repairing "$FIXER_REPORT" "$feature_id"
expect_success 'a valid feature finding reopens the second listed VERIFIED slice' \
  "$SCRIPT" "$reentry_plan" 2 repairing "$FIXER_REPORT" "$feature_id"
expect_file_contains 'first listed feature slice gate reopens' \
  "$reentry_tasks" '- [ ] 1.V **Slice verification gate**'
expect_file_contains 'second listed feature slice gate reopens' \
  "$reentry_tasks" '- [ ] 2.V **Slice verification gate**'
expect_file_contains 'an unlisted VERIFIED slice remains unchanged' \
  "$reentry_tasks" '- [x] 3.V **Slice verification gate**'

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
