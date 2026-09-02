#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
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
workspace_sha() {
  find "$1" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{ print $1 }'
}

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
    '## 1. Finding boundary' \
    '**Slice state:** [ ] QUEUED' \
    '' \
    '- [ ] 1.1 Exercise finding state' \
    '- [ ] 1.V **Slice verification gate**' >"$TASKS"
  printf 'fixture\n' >"$REPO/README.md"
  git -C "$REPO" add README.md openspec
  git -C "$REPO" commit -qm 'chore: fixture'
  DISPATCH="$TEST_ROOT/$name-dispatch.md"
  RESULT="$TEST_ROOT/$name-result.md"
  printf 'Dispatch: %s\n' "$name" >"$DISPATCH"
  printf 'Status: PASS\n' >"$RESULT"
  expect_success "$name initializes v1" "$FINDING_STATE" "$PLAN" init
}

make_two_slice_fixture() {
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
    '## 1. First finding boundary' \
    '**Slice state:** [ ] QUEUED' \
    '' \
    '- [ ] 1.1 Exercise the first finding state' \
    '- [ ] 1.V **Slice verification gate**' \
    '' \
    '## 2. Second finding boundary' \
    '**Slice state:** [ ] QUEUED' \
    '' \
    '- [ ] 2.1 Exercise the second finding state' \
    '- [ ] 2.V **Slice verification gate**' >"$TASKS"
  printf 'fixture\n' >"$REPO/README.md"
  git -C "$REPO" add README.md openspec
  git -C "$REPO" commit -qm 'chore: fixture'
  DISPATCH="$TEST_ROOT/$name-dispatch.md"
  RESULT="$TEST_ROOT/$name-result.md"
  printf 'Dispatch: %s\n' "$name" >"$DISPATCH"
  printf 'Status: PASS\n' >"$RESULT"
  expect_success "$name initializes v1" "$FINDING_STATE" "$PLAN" init
}

claim() {
  local obligation=$1 actor=$2
  local claim_output
  if claim_output=$("$WORKFLOW_STATE" "$PLAN" claim "$obligation" "$actor" "$DISPATCH" 2>&1); then
    LAST_RECEIPT=$(printf '%s\n' "$claim_output" | sed -n 's/^Receipt: //p')
    record_pass "claim $obligation"
  else
    LAST_RECEIPT=''
    record_fail "claim $obligation"
    printf '      %s\n' "$claim_output"
  fi
}

complete_obligation() {
  local obligation=$1 actor=$2
  local origin role_report findings_dir final_suite role_status=PASS
  case "$obligation" in
    slice-*-cleaner) origin=Cleaner ;;
    slice-*-architect) origin=Architect ;;
    slice-*-security) origin='Security Reviewer' ;;
    slice-*-hardener) origin=Hardener ;;
    slice-*-qa) origin=QA ;;
    feature-branch-review) origin='Branch Reviewer' ;;
    slice-*-final-suite|slice-*-verified)
      record_pass "accept $obligation through the QA macro"
      return
      ;;
    *)
      claim "$obligation" "$actor"
      expect_success "accept $obligation" "$WORKFLOW_STATE" "$PLAN" accept "$LAST_RECEIPT" PASS "$RESULT"
      return
      ;;
  esac
  claim "$obligation" "$actor"
  ROLE_RESULT_NUMBER=$((ROLE_RESULT_NUMBER + 1))
  role_report="$TEST_ROOT/role-result-$ROLE_RESULT_NUMBER.md"
  findings_dir="$TEST_ROOT/role-findings-$ROLE_RESULT_NUMBER"
  mkdir -p "$findings_dir"
  case "$origin" in Hardener|QA) role_status=VERIFIED ;; esac
  printf 'Status: %s\nFinding count: 0\n' "$role_status" >"$role_report"
  if [ "$origin" = QA ]; then
    final_suite="$TEST_ROOT/final-suite-$ROLE_RESULT_NUMBER.md"
    printf 'Status: PASS\n' >"$final_suite"
    expect_success "accept $obligation" env GDD_FINDINGS_DIR="$findings_dir" \
      "$WORKFLOW_STATE" "$PLAN" accept-active "$obligation" SliceVerifiedMacro "$role_report" "$final_suite"
  else
    expect_success "accept $obligation" env GDD_FINDINGS_DIR="$findings_dir" \
      "$WORKFLOW_STATE" "$PLAN" accept-active "$obligation" PASS "$role_report"
  fi
}

claim_origin_obligation() {
  local origin=$1
  complete_obligation slice-1-implementer implementer
  case "$origin" in
    Cleaner) claim slice-1-cleaner cleaner ;;
    Architect)
      complete_obligation slice-1-cleaner cleaner
      claim slice-1-architect architect
      ;;
    'Security Reviewer')
      complete_obligation slice-1-cleaner cleaner
      complete_obligation slice-1-architect architect
      claim slice-1-security security-reviewer
      ;;
    Hardener)
      complete_obligation slice-1-cleaner cleaner
      complete_obligation slice-1-architect architect
      complete_obligation slice-1-security security-reviewer
      claim slice-1-hardener hardener
      ;;
    QA)
      complete_obligation slice-1-cleaner cleaner
      complete_obligation slice-1-architect architect
      complete_obligation slice-1-security security-reviewer
      complete_obligation slice-1-hardener hardener
      claim slice-1-qa qa
      ;;
  esac
}

write_report() {
  local output=$1 origin=$2 complete=${3:-yes}
  if [ "$complete" = no ]; then
    printf 'Origin role: %s\nObserved failure: Missing controller fields.\n' "$origin" >"$output"
    return
  fi
  printf '%s\n' \
    "Origin role: $origin" \
    'Severity claim: Important' \
    'Blocking claim: yes' \
    'Observed failure: The recorded boundary is incomplete.' \
    'Evidence: reports/review.md' \
    'Violated authority: approved design' \
    'Assumptions: The journal is authoritative.' \
    'Failure scenario: A lifecycle role advances without adjudication.' \
    'Proposed repair: Replay the affected boundary.' \
    'Repair effects: The required roles rerun.' >"$output"
}

write_role_report() {
  local output=$1 finding_count=$2 role_status=${3:-PASS}
  printf 'Status: %s\nFinding count: %s\n' "$role_status" "$finding_count" >"$output"
}

report_one() {
  local scope=$1 origin=$2 finding_report=$3
  local role_report findings_dir final_suite result role_status=PASS
  ROLE_RESULT_NUMBER=$((ROLE_RESULT_NUMBER + 1))
  role_report="$TEST_ROOT/role-report-$ROLE_RESULT_NUMBER.md"
  findings_dir="$TEST_ROOT/report-findings-$ROLE_RESULT_NUMBER"
  mkdir -p "$findings_dir"
  case "$origin" in Hardener|QA) role_status=VERIFIED ;; esac
  write_role_report "$role_report" 1 "$role_status"
  cp "$finding_report" "$findings_dir/1.md"
  if [ "$origin" = QA ]; then
    final_suite="$TEST_ROOT/report-final-suite-$ROLE_RESULT_NUMBER.md"
    printf 'Status: PASS\n' >"$final_suite"
    result=$("$FINDING_STATE" "$PLAN" report "$scope" "$origin" "$role_report" "$findings_dir" "$final_suite")
  else
    result=$("$FINDING_STATE" "$PLAN" report "$scope" "$origin" "$role_report" "$findings_dir")
  fi
  printf '%s\n' "$result" | sed -n '1p'
}

ROLE_RESULT_NUMBER=0

write_ruling() {
  local output=$1 disposition=$2
  printf '%s\n' \
    "Disposition: $disposition" \
    'Ruling: The evidence does not justify an immediate repair.' \
    'Cost if wrong: A later role could rely on stale evidence.' \
    'Wake condition: New evidence contradicts this ruling.' \
    'Fable result: UNAVAILABLE: deterministic fixture' >"$output"
}

origin_obligation_id() {
  case "$1" in
    Cleaner) printf '%s\n' slice-1-cleaner ;;
    Architect) printf '%s\n' slice-1-architect ;;
    'Security Reviewer') printf '%s\n' slice-1-security ;;
    Hardener) printf '%s\n' slice-1-hardener ;;
    QA) printf '%s\n' slice-1-qa ;;
    'Branch Reviewer') printf '%s\n' feature-branch-review ;;
  esac
}

make_fixture no-receipt
REPORT="$TEST_ROOT/no-receipt-report.md"
write_report "$REPORT" Cleaner
ROLE_REPORT="$TEST_ROOT/no-receipt-role.md"
FINDINGS_DIR="$TEST_ROOT/no-receipt-findings"
mkdir -p "$FINDINGS_DIR"
write_role_report "$ROLE_REPORT" 1
cp "$REPORT" "$FINDINGS_DIR/1.md"
before=$(workspace_sha "$WORKSPACE")
expect_failure 'report requires an active lifecycle receipt' "$FINDING_STATE" "$PLAN" report 1 Cleaner "$ROLE_REPORT" "$FINDINGS_DIR"
[ "$before" = "$(workspace_sha "$WORKSPACE")" ] && record_pass 'unclaimed report leaves the journal unchanged' || record_fail 'unclaimed report leaves the journal unchanged'

for origin in Cleaner Architect 'Security Reviewer' Hardener QA; do
  slug=$(printf '%s' "$origin" | tr '[:upper:] ' '[:lower:]-')
  make_fixture "origin-$slug"
  REPORT="$TEST_ROOT/origin-$slug.md"
  write_report "$REPORT" "$origin"
  claim_origin_obligation "$origin"
  finding_id=$(report_one 1 "$origin" "$REPORT")
  [ "$finding_id" = GDD-F0001 ] && record_pass "$origin receives an engine ID" || record_fail "$origin receives an engine ID"
  status_output=$("$WORKFLOW_STATE" "$PLAN" status)
  printf '%s\n' "$status_output" | grep -qF 'Active claim: none' && record_pass "$origin report consumes the role claim" || record_fail "$origin report consumes the role claim"
  printf '%s\n' "$status_output" | grep -qF 'finding-GDD-F0001-verify COMPLETE' && record_pass "$origin creates VERIFY_FINDING" || record_fail "$origin creates VERIFY_FINDING"
  printf '%s\n' "$status_output" | grep -qF 'finding-GDD-F0001-dispose READY' && record_pass "$origin creates DISPOSE_FINDING" || record_fail "$origin creates DISPOSE_FINDING"
  metadata=$(find "$WORKSPACE/workflow-v1/events" -name metadata.tsv -type f -print | while IFS= read -r candidate; do
    grep -qxF $'finding-origin\t'"$origin" "$candidate" && { printf '%s\n' "$candidate"; break; }
  done)
  expect_contains "$origin metadata records canonical origin" "$metadata" $'finding-origin\t'"$origin"
done

make_fixture branch-origin
for obligation_actor in \
  'slice-1-implementer implementer' \
  'slice-1-cleaner cleaner' \
  'slice-1-architect architect' \
  'slice-1-security security-reviewer' \
  'slice-1-hardener hardener' \
  'slice-1-qa qa' \
  'slice-1-final-suite controller' \
  'slice-1-verified controller'; do
  obligation=${obligation_actor% *}
  actor=${obligation_actor##* }
  complete_obligation "$obligation" "$actor"
done
claim feature-branch-review branch-reviewer
BRANCH_REPORT="$TEST_ROOT/branch-report.md"
write_report "$BRANCH_REPORT" 'Branch Reviewer'
branch_id=$(report_one feature 'Branch Reviewer' "$BRANCH_REPORT")
[ "$branch_id" = GDD-F0001 ] && record_pass 'Branch Reviewer receives an engine ID' || record_fail 'Branch Reviewer receives an engine ID'
expect_contains 'Branch Reviewer finding records feature scope' "$WORKSPACE/findings.tsv" $'\tfeature\tBranch Reviewer\t'

make_fixture supplement
INCOMPLETE="$TEST_ROOT/incomplete.md"
COMPLETE="$TEST_ROOT/complete.md"
write_report "$INCOMPLETE" Cleaner no
write_report "$COMPLETE" Cleaner
complete_obligation slice-1-implementer implementer
claim slice-1-cleaner cleaner
ROLE_REPORT="$TEST_ROOT/incomplete-role.md"
FINDINGS_DIR="$TEST_ROOT/incomplete-findings"
mkdir -p "$FINDINGS_DIR"
write_role_report "$ROLE_REPORT" 1
cp "$INCOMPLETE" "$FINDINGS_DIR/1.md"
expect_failure 'incomplete grouped finding cannot advance Cleaner' \
  "$FINDING_STATE" "$PLAN" report 1 Cleaner "$ROLE_REPORT" "$FINDINGS_DIR"
status_output=$("$WORKFLOW_STATE" "$PLAN" status)
printf '%s\n' "$status_output" | grep -qF 'Active claim: slice-1-cleaner' && record_pass 'incomplete grouped finding preserves the role claim' || record_fail 'incomplete grouped finding preserves the role claim'
incomplete_id=$(report_one 1 Cleaner "$COMPLETE")
claim "finding-$incomplete_id-dispose" controller
RULING="$TEST_ROOT/dismissed.md"
write_ruling "$RULING" DISMISSED
expect_success 'terminal disposition uses DISPOSE_FINDING' "$FINDING_STATE" "$PLAN" transition "$incomplete_id" DISMISSED "$RULING"
for obligation_actor in \
  'slice-1-architect architect' \
  'slice-1-security security-reviewer' \
  'slice-1-hardener hardener' \
  'slice-1-qa qa' \
  'slice-1-final-suite controller' \
  'slice-1-verified controller' \
  'feature-branch-review branch-reviewer'; do
  obligation=${obligation_actor% *}
  actor=${obligation_actor##* }
  complete_obligation "$obligation" "$actor"
done
claim feature-findings-digest controller
DIGEST="$WORKSPACE/findings.md"
expect_success 'digest is accepted through its obligation' "$FINDING_STATE" "$PLAN" digest "$DIGEST"
expect_contains 'digest includes unchanged finding' "$DIGEST" "\`$incomplete_id\`"
claim "finding-$incomplete_id-wake" controller
WAKE="$TEST_ROOT/wake.md"
printf 'Wake evidence: New evidence contradicts the ruling.\n' >"$WAKE"
expect_success 'wake evidence returns the finding to REPORTED' "$FINDING_STATE" "$PLAN" transition "$incomplete_id" REPORTED "$WAKE"
expect_contains 'wake is regenerated in the finding projection' "$WORKSPACE/findings.tsv" $'\tREPORTED\t'

for mandatory_origin in Hardener QA; do
  slug=$(printf '%s' "$mandatory_origin" | tr '[:upper:]' '[:lower:]')
  make_fixture "mandatory-$slug"
  REPORT="$TEST_ROOT/mandatory-$slug.md"
  write_report "$REPORT" "$mandatory_origin"
  claim_origin_obligation "$mandatory_origin"
  mandatory_id=$(report_one 1 "$mandatory_origin" "$REPORT")
  claim "finding-$mandatory_id-dispose" controller
  write_ruling "$RULING" DISMISSED
  expect_success "$mandatory_origin finding can be dismissed" "$FINDING_STATE" "$PLAN" transition "$mandatory_id" DISMISSED "$RULING"
  mandatory_status=$(awk -F '\t' -v id="slice-1-$slug" '$1 == id { print $2 }' "$WORKSPACE/workflow-v1/projections/status.tsv")
  [ "$mandatory_status" = COMPLETE ] && record_pass "$mandatory_origin grouped result is accepted" || record_fail "$mandatory_origin grouped result is accepted"
done

make_fixture blocked-boundary
FIRST_REPORT="$TEST_ROOT/blocked-first.md"
SECOND_REPORT="$TEST_ROOT/blocked-second.md"
write_report "$FIRST_REPORT" Cleaner
write_report "$SECOND_REPORT" Cleaner
sed 's/The recorded boundary is incomplete/A second independent finding remains ready/' "$SECOND_REPORT" >"$SECOND_REPORT.updated"
mv "$SECOND_REPORT.updated" "$SECOND_REPORT"
complete_obligation slice-1-implementer implementer
claim slice-1-cleaner cleaner
ROLE_REPORT="$TEST_ROOT/blocked-role.md"
FINDINGS_DIR="$TEST_ROOT/blocked-findings"
mkdir -p "$FINDINGS_DIR"
write_role_report "$ROLE_REPORT" 2
cp "$FIRST_REPORT" "$FINDINGS_DIR/1.md"
cp "$SECOND_REPORT" "$FINDINGS_DIR/2.md"
blocked_ids=$("$FINDING_STATE" "$PLAN" report 1 Cleaner "$ROLE_REPORT" "$FINDINGS_DIR")
first_blocked_id=$(printf '%s\n' "$blocked_ids" | sed -n '1p')
second_ready_id=$(printf '%s\n' "$blocked_ids" | sed -n '2p')
[ -n "$first_blocked_id" ] && [ -n "$second_ready_id" ] \
  && record_pass 'Cleaner result accepts both grouped findings' \
  || record_fail 'Cleaner result accepts both grouped findings'
claim "finding-$first_blocked_id-dispose" controller
BLOCKED_RULING="$TEST_ROOT/blocked-boundary.md"
write_ruling "$BLOCKED_RULING" BLOCKED
printf 'Blocked boundary: slice-1-architect\n' >>"$BLOCKED_RULING"
expect_success 'BLOCKED persists its exact dependency boundary' \
  "$FINDING_STATE" "$PLAN" transition "$first_blocked_id" BLOCKED "$BLOCKED_RULING"
expect_contains 'BLOCKED metadata records the dependency boundary' \
  "$WORKSPACE/workflow-v1/events/event-8/metadata.tsv" $'blocking-boundary\tslice-1-architect'
"$WORKFLOW_STATE" "$PLAN" status >/dev/null
blocked_boundary_status=$(awk -F '\t' '$1 == "slice-1-architect" { print $2 }' "$WORKSPACE/workflow-v1/projections/status.tsv")
[ "$blocked_boundary_status" = PENDING ] \
  && record_pass 'only the recorded static boundary is blocked' \
  || record_fail 'only the recorded static boundary is blocked'
next_output=$("$WORKFLOW_STATE" "$PLAN" next)
[ "$(printf '%s\n' "$next_output" | sed -n 's/^Ready obligation: //p')" = "finding-$second_ready_id-dispose" ] \
  && record_pass 'unrelated ready work is selected before the BLOCKED wake' \
  || record_fail 'unrelated ready work is selected before the BLOCKED wake'

make_two_slice_fixture feature-repair-invalidation
for obligation_actor in \
  'slice-1-implementer implementer' \
  'slice-1-cleaner cleaner' \
  'slice-1-architect architect' \
  'slice-1-security security-reviewer' \
  'slice-1-hardener hardener' \
  'slice-1-qa qa' \
  'slice-1-final-suite controller' \
  'slice-1-verified controller' \
  'slice-2-implementer implementer' \
  'slice-2-cleaner cleaner' \
  'slice-2-architect architect' \
  'slice-2-security security-reviewer' \
  'slice-2-hardener hardener' \
  'slice-2-qa qa' \
  'slice-2-final-suite controller' \
  'slice-2-verified controller'; do
  obligation=${obligation_actor% *}
  actor=${obligation_actor##* }
  complete_obligation "$obligation" "$actor"
done
claim feature-branch-review branch-reviewer
FEATURE_REPORT="$TEST_ROOT/feature-repair-report.md"
write_report "$FEATURE_REPORT" 'Branch Reviewer'
feature_id=$(report_one feature 'Branch Reviewer' "$FEATURE_REPORT")
claim "finding-$feature_id-dispose" controller
UNKNOWN_SLICE_REPAIRING="$TEST_ROOT/feature-repairing-unknown-slice.md"
printf 'Repair hypothesis: Replay an unknown affected slice.\nRepair base: %s\nReplay through: QA\nAffected slices: 1,999\n' \
  "$(git -C "$REPO" rev-parse HEAD)" >"$UNKNOWN_SLICE_REPAIRING"
before_unknown_slice_repair=$(workspace_sha "$WORKSPACE")
# Break caught: normalized positive slice numbers are not sufficient when the static workflow has no matching slice.
expect_failure 'feature repair rejects an unknown affected slice' \
  "$FINDING_STATE" "$PLAN" transition "$feature_id" REPAIRING "$UNKNOWN_SLICE_REPAIRING"
after_unknown_slice_repair=$(workspace_sha "$WORKSPACE")
[ "$before_unknown_slice_repair" = "$after_unknown_slice_repair" ] \
  && record_pass 'unknown affected slice rejection leaves the workspace unchanged' \
  || record_fail 'unknown affected slice rejection leaves the workspace unchanged'
FEATURE_REPAIRING="$TEST_ROOT/feature-repairing.md"
printf 'Repair hypothesis: Replay both affected slices through QA.\nRepair base: %s\nReplay through: QA\nAffected slices: 1,2\n' \
  "$(git -C "$REPO" rev-parse HEAD)" >"$FEATURE_REPAIRING"
expect_success 'feature finding enters the final repair wave' \
  "$FINDING_STATE" "$PLAN" transition "$feature_id" REPAIRING "$FEATURE_REPAIRING"
feature_invalidations=$(awk -F '\t' '$5 == "EvidenceInvalidated" { print $4 }' "$WORKSPACE/workflow-v1/events.tsv" | paste -sd, -)
[ "$feature_invalidations" = 'slice-1-cleaner,slice-1-architect,slice-1-security,slice-1-hardener,slice-1-qa,slice-2-cleaner,slice-2-architect,slice-2-security,slice-2-hardener,slice-2-qa' ] \
  && record_pass 'feature repair invalidates Cleaner through QA for every affected slice' \
  || record_fail 'feature repair invalidates Cleaner through QA for every affected slice'
for affected_slice in 1 2; do
  qa_status=$(awk -F '\t' -v id="slice-$affected_slice-qa" '$1 == id { print $2 }' "$WORKSPACE/workflow-v1/projections/status.tsv")
  [ "$qa_status" != COMPLETE ] \
    && record_pass "feature repair invalidates slice $affected_slice QA" \
    || record_fail "feature repair invalidates slice $affected_slice QA"
done

claim "finding-$feature_id-replay-entry" controller
expect_success 'feature repair enters replay through its receipt' \
  "$FINDING_STATE" "$PLAN" repair-entry 1 "$feature_id"
claim "finding-$feature_id-repair-start-1" fixer
FEATURE_REPAIR_START="$TEST_ROOT/feature-repair-start.md"
printf 'Repair round: 1\nExecutor: fixer\nAgent ID: feature-fixer-one\nRepair hypothesis: Replay both affected slices through QA.\n' >"$FEATURE_REPAIR_START"
expect_success 'feature repair round starts through its receipt' \
  "$FINDING_STATE" "$PLAN" repair-start "$feature_id" "$FEATURE_REPAIR_START"
claim "finding-$feature_id-repair-finish-1" fixer
FEATURE_REPLAY="$TEST_ROOT/feature-replay.md"
printf 'Both affected slices require fresh replay.\n' >"$FEATURE_REPLAY"
FEATURE_REPAIR_FINISH="$TEST_ROOT/feature-repair-finish.md"
printf 'Repair round: 1\nExecutor: fixer\nAgent ID: feature-fixer-one\nRepair head: %s\nReplay status: VERIFIED\nReplay evidence: %s\n' \
  "$(git -C "$REPO" rev-parse HEAD)" "$FEATURE_REPLAY" >"$FEATURE_REPAIR_FINISH"
expect_success 'feature repair finish records verified replay' \
  "$FINDING_STATE" "$PLAN" repair-finish "$feature_id" "$FEATURE_REPAIR_FINISH"
claim "finding-$feature_id-repair-result" fixer
expect_success 'feature repair result starts static replay' \
  env GDD_FINDING_ID="$feature_id" GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Branch Reviewer' \
    GDD_FINDING_STATE=REPAIRING GDD_FINDING_EVENT_NAME=repair-result GDD_TARGET_SLICE=1 \
    "$WORKFLOW_STATE" "$PLAN" accept-active "finding-$feature_id-repair-result" RepairAccepted "$RESULT"
for replay_obligation_actor in \
  'slice-1-cleaner cleaner' \
  'slice-1-architect architect' \
  'slice-1-security security-reviewer' \
  'slice-1-hardener hardener' \
  'slice-1-qa qa'; do
  replay_obligation=${replay_obligation_actor% *}
  replay_actor=${replay_obligation_actor##* }
  complete_obligation "$replay_obligation" "$replay_actor"
done
# Break caught: feature replay completion cannot be inferred from only the first affected slice.
expect_failure 'feature resolution remains blocked after only one affected slice replays' \
  "$WORKFLOW_STATE" "$PLAN" claim "finding-$feature_id-resolve" controller "$DISPATCH"
for replay_obligation_actor in \
  'slice-2-cleaner cleaner' \
  'slice-2-architect architect' \
  'slice-2-security security-reviewer' \
  'slice-2-hardener hardener' \
  'slice-2-qa qa'; do
  replay_obligation=${replay_obligation_actor% *}
  replay_actor=${replay_obligation_actor##* }
  complete_obligation "$replay_obligation" "$replay_actor"
done
claim "finding-$feature_id-resolve" controller
expect_success 'feature resolution succeeds after every affected slice replays' \
  "$FINDING_STATE" "$PLAN" transition "$feature_id" RESOLVED "$FEATURE_REPAIR_FINISH"

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
