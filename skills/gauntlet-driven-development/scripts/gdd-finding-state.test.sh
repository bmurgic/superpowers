#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FINDING_STATE="$SCRIPT_DIR/gdd-finding-state"
WORKFLOW_STATE="$SCRIPT_DIR/gdd-workflow-state"
SLICE_STATE="$SCRIPT_DIR/gdd-slice-state"
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

journal_and_findings_sha() {
  local workspace=$1
  {
    shasum -a 256 "$workspace/workflow-v1/events.tsv"
    find "$workspace/workflow-v1/events" -type f -print0 | sort -z | xargs -0 shasum -a 256
    shasum -a 256 "$workspace/findings.tsv"
  } | shasum -a 256 | awk '{ print $1 }'
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
  printf 'Status: DONE\n' >"$RESULT"
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
  printf 'Status: DONE\n' >"$RESULT"
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
    slice-*-review) origin='Task Reviewer' ;;
    feature-security-review) origin='Security Reviewer' ;;
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
  LAST_ROLE_REPORT=$role_report
  findings_dir="$TEST_ROOT/role-findings-$ROLE_RESULT_NUMBER"
  mkdir -p "$findings_dir"
  case "$origin" in Hardener|QA) role_status=VERIFIED ;; esac
  printf 'Status: %s\nFinding count: 0\n' "$role_status" >"$role_report"
  if [ "$origin" = QA ]; then
    final_suite="$TEST_ROOT/final-suite-$ROLE_RESULT_NUMBER.md"
    printf 'Status: PASS\n' >"$final_suite"
    expect_success "accept $obligation" env GDD_FINDINGS_DIR="$findings_dir" \
      "$WORKFLOW_STATE" "$PLAN" accept-active "$obligation" SliceVerifiedMacro "$role_report" "$final_suite"
  elif [ "$origin" = 'Task Reviewer' ] || [ "$origin" = 'Security Reviewer' ]; then
    scope=1
    [ "$origin" != 'Security Reviewer' ] || scope=feature
    expect_success "accept $obligation" "$FINDING_STATE" "$PLAN" report "$scope" "$origin" "$role_report" "$findings_dir"
  else
    expect_success "accept $obligation" env GDD_FINDINGS_DIR="$findings_dir" \
      "$WORKFLOW_STATE" "$PLAN" accept-active "$obligation" PASS "$role_report"
  fi
}

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
      claim slice-1-qa qa
      ;;
    *) record_fail "unknown origin for fixture: $origin" ;;
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

report_two() {
  local scope=$1 origin=$2 first_finding_report=$3 second_finding_report=$4
  local role_report findings_dir result
  ROLE_RESULT_NUMBER=$((ROLE_RESULT_NUMBER + 1))
  role_report="$TEST_ROOT/role-report-$ROLE_RESULT_NUMBER.md"
  findings_dir="$TEST_ROOT/report-findings-$ROLE_RESULT_NUMBER"
  mkdir -p "$findings_dir"
  write_role_report "$role_report" 2 PASS
  cp "$first_finding_report" "$findings_dir/1.md"
  cp "$second_finding_report" "$findings_dir/2.md"
  result=$("$FINDING_STATE" "$PLAN" report "$scope" "$origin" "$role_report" "$findings_dir")
  printf '%s\n' "$result" | paste -sd, -
}

ROLE_RESULT_NUMBER=0

write_ruling() {
  local output=$1 disposition=$2 fable_result
  if [ "$disposition" = BLOCKED ]; then
    fable_result='Fable result: UNAVAILABLE: deterministic fixture'
  else
    printf '%s\n' 'Advice: the disposition is defensible.' >"$output.fable"
    fable_result="Fable result: $output.fable"
  fi
  printf '%s\n' \
    "Disposition: $disposition" \
    'Ruling: The evidence does not justify an immediate repair.' \
    'Cost if wrong: A later role could rely on stale evidence.' \
    'Wake condition: New evidence contradicts this ruling.' \
    "$fable_result" >"$output"
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

origin_obligation_id() {
  case "$1" in
    'Task Reviewer') printf '%s\n' slice-1-review ;;
    Cleaner) printf '%s\n' slice-1-cleaner ;;
    Architect) printf '%s\n' slice-1-architect ;;
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

for origin in 'Task Reviewer' Cleaner Architect Hardener QA; do
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

make_fixture hardener-failed-finding
HARDENER_FINDING_REPORT="$TEST_ROOT/hardener-failed-finding.md"
write_report "$HARDENER_FINDING_REPORT" Hardener
HARDENER_FAILED_ROLE_REPORT="$TEST_ROOT/hardener-not-verified.md"
HARDENER_FAILED_FINDINGS="$TEST_ROOT/hardener-not-verified-findings"
mkdir -p "$HARDENER_FAILED_FINDINGS"
write_role_report "$HARDENER_FAILED_ROLE_REPORT" 1 'NOT VERIFIED'
cp "$HARDENER_FINDING_REPORT" "$HARDENER_FAILED_FINDINGS/1.md"
claim_origin_obligation Hardener
expect_success 'Hardener NOT VERIFIED finding atomically records a retryable failure' \
  "$FINDING_STATE" "$PLAN" report 1 Hardener "$HARDENER_FAILED_ROLE_REPORT" "$HARDENER_FAILED_FINDINGS"
expect_contains 'Hardener failed finding receives an engine ID' "$WORKSPACE/findings.tsv" $'\tHardener\tREPORTED\t'
hardener_state=$(awk -F '\t' '$1 == "slice-1-hardener" { print $2 }' "$WORKSPACE/workflow-v1/projections/status.tsv")
[ "$hardener_state" = READY ] \
  && record_pass 'Hardener failure leaves its static gate retryable' \
  || record_fail 'Hardener failure leaves its static gate retryable'
status_output=$("$WORKFLOW_STATE" "$PLAN" status)
printf '%s\n' "$status_output" | grep -qF 'Active claim: none' \
  && record_pass 'Hardener failed finding closes the lifecycle claim' \
  || record_fail 'Hardener failed finding closes the lifecycle claim'
[ "$(awk -F '\t' '$4 == "slice-1-final-suite" || $4 == "slice-1-verified" { count++ } END { print count + 0 }' "$WORKSPACE/workflow-v1/events.tsv")" = 0 ] \
  && record_pass 'Hardener failure creates no QA completion events' \
  || record_fail 'Hardener failure creates no QA completion events'

make_fixture qa-failed-finding
QA_FINDING_REPORT="$TEST_ROOT/qa-failed-finding.md"
write_report "$QA_FINDING_REPORT" QA
QA_FAILED_ROLE_REPORT="$TEST_ROOT/qa-not-verified.md"
QA_FAILED_FINDINGS="$TEST_ROOT/qa-not-verified-findings"
mkdir -p "$QA_FAILED_FINDINGS"
write_role_report "$QA_FAILED_ROLE_REPORT" 1 'NOT VERIFIED'
cp "$QA_FINDING_REPORT" "$QA_FAILED_FINDINGS/1.md"
claim_origin_obligation QA
expect_success 'QA NOT VERIFIED finding atomically records a retryable failure without a final suite' \
  "$FINDING_STATE" "$PLAN" report 1 QA "$QA_FAILED_ROLE_REPORT" "$QA_FAILED_FINDINGS"
expect_contains 'QA failed finding receives an engine ID' "$WORKSPACE/findings.tsv" $'\tQA\tREPORTED\t'
qa_state=$(awk -F '\t' '$1 == "slice-1-qa" { print $2 }' "$WORKSPACE/workflow-v1/projections/status.tsv")
[ "$qa_state" = READY ] \
  && record_pass 'QA failure leaves its static gate retryable' \
  || record_fail 'QA failure leaves its static gate retryable'
status_output=$("$WORKFLOW_STATE" "$PLAN" status)
printf '%s\n' "$status_output" | grep -qF 'Active claim: none' \
  && record_pass 'QA failed finding closes the lifecycle claim' \
  || record_fail 'QA failed finding closes the lifecycle claim'
[ "$(awk -F '\t' '$4 == "slice-1-final-suite" || $4 == "slice-1-verified" { count++ } END { print count + 0 }' "$WORKSPACE/workflow-v1/events.tsv")" = 0 ] \
  && record_pass 'QA failure creates no final-suite or verification event' \
  || record_fail 'QA failure creates no final-suite or verification event'

make_fixture qa-failed-malformed-group
MALFORMED_QA_REPORT="$TEST_ROOT/qa-malformed-not-verified.md"
MALFORMED_QA_FINDINGS="$TEST_ROOT/qa-malformed-not-verified-findings"
mkdir -p "$MALFORMED_QA_FINDINGS"
write_role_report "$MALFORMED_QA_REPORT" 1 'NOT VERIFIED'
printf 'Origin role: QA\n' >"$MALFORMED_QA_FINDINGS/1.md"
claim_origin_obligation QA
before_malformed_qa=$(journal_and_findings_sha "$WORKSPACE")
expect_failure 'malformed QA NOT VERIFIED finding group is rejected atomically' \
  "$FINDING_STATE" "$PLAN" report 1 QA "$MALFORMED_QA_REPORT" "$MALFORMED_QA_FINDINGS"
[ "$before_malformed_qa" = "$(journal_and_findings_sha "$WORKSPACE")" ] \
  && record_pass 'malformed QA failure leaves journal and findings unchanged' \
  || record_fail 'malformed QA failure leaves journal and findings unchanged'

make_fixture branch-origin
for obligation_actor in \
  'slice-1-implementer implementer' \
  'slice-1-review task-reviewer' \
  'slice-1-cleaner cleaner' \
  'slice-1-architect architect' \
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
complete_obligation slice-1-review task-reviewer
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
RULING="$TEST_ROOT/dismissed.md"
write_ruling "$RULING" DISMISSED
claim "finding-$incomplete_id-consult-1" controller
write_consult "$TEST_ROOT/supplement-consult.md" "$incomplete_id" C5 NO_FIX
"$FINDING_STATE" "$PLAN" consult "$incomplete_id" "$TEST_ROOT/supplement-consult.md"
claim "finding-$incomplete_id-dispose" controller
expect_success 'terminal disposition uses DISPOSE_FINDING' "$FINDING_STATE" "$PLAN" transition "$incomplete_id" DISMISSED "$RULING"
for obligation_actor in \
  'slice-1-architect architect' \
  'slice-1-hardener hardener' \
  'slice-1-qa qa' \
  'slice-1-final-suite controller' \
  'slice-1-verified controller' \
  'feature-branch-review branch-reviewer' \
  'feature-security-review security-reviewer'; do
  obligation=${obligation_actor% *}
  actor=${obligation_actor##* }
  complete_obligation "$obligation" "$actor"
done
claim feature-findings-digest controller
DIGEST="$WORKSPACE/findings.md"
expect_success 'digest is accepted through its obligation' "$FINDING_STATE" "$PLAN" digest "$DIGEST"
expect_contains 'digest includes unchanged finding' "$DIGEST" "\`$incomplete_id\`"
expect_contains 'the digest lists the consultation' "$DIGEST" '## Advisor consultations'
expect_contains 'the digest lists the consultation case' "$DIGEST" 'Case: C5'
claim "finding-$incomplete_id-wake" controller
WAKE="$TEST_ROOT/wake.md"
printf 'Wake evidence: New evidence contradicts the ruling.\n' >"$WAKE"
expect_success 'wake evidence returns the finding to REPORTED' "$FINDING_STATE" "$PLAN" transition "$incomplete_id" REPORTED "$WAKE"
expect_contains 'wake is regenerated in the finding projection' "$WORKSPACE/findings.tsv" $'\tREPORTED\t'

make_two_slice_fixture parked-wake-before-dependent
WAKE_REPORT="$TEST_ROOT/parked-wake-report.md"
write_report "$WAKE_REPORT" Architect
complete_obligation slice-1-implementer implementer
complete_obligation slice-1-review task-reviewer
complete_obligation slice-1-cleaner cleaner
claim slice-1-architect architect
wake_id=$(report_one 1 Architect "$WAKE_REPORT")
claim "finding-$wake_id-dispose" controller
PARKED_RULING="$TEST_ROOT/parked-wake-ruling.md"
write_ruling "$PARKED_RULING" PARKED
sed -i.bak 's|^Fable result: .*|Fable result: UNAVAILABLE: advisor plugin missing|' "$PARKED_RULING"
rm "$PARKED_RULING.bak"
expect_failure 'PARKED without Fable requires a recorded user ruling' \
  "$FINDING_STATE" "$PLAN" transition "$wake_id" PARKED "$PARKED_RULING"
printf '%s\n' 'User ruling: park this finding until the next slice.' >"$TEST_ROOT/parked-user-authority.md"
printf 'User authority: %s\n' "$TEST_ROOT/parked-user-authority.md" >>"$PARKED_RULING"
expect_success 'dependent finding can be parked before the dependent slice is ready' \
  "$FINDING_STATE" "$PLAN" transition "$wake_id" PARKED "$PARKED_RULING"
for obligation_actor in \
  'slice-1-hardener hardener' \
  'slice-1-qa qa' \
  'slice-1-final-suite controller' \
  'slice-1-verified controller'; do
  obligation=${obligation_actor% *}
  actor=${obligation_actor##* }
  complete_obligation "$obligation" "$actor"
done
next_output=$("$WORKFLOW_STATE" "$PLAN" next)
[ "$(printf '%s\n' "$next_output" | sed -n 's/^Ready obligation: //p')" = 'slice-2-implementer' ] \
  && record_pass 'the dependent slice is selected before the controller wake check' \
  || record_fail 'the dependent slice is selected before the controller wake check'
claim "finding-$wake_id-wake" controller
INVALID_WAKE="$TEST_ROOT/invalid-wake.md"
printf 'Updated ruling: The dependency now consumes the parked interface.\n' >"$INVALID_WAKE"
before_invalid_wake=$(workspace_sha "$WORKSPACE")
expect_failure 'invalid wake evidence is rejected before the dependent slice is claimed' \
  "$FINDING_STATE" "$PLAN" transition "$wake_id" REPORTED "$INVALID_WAKE"
[ "$before_invalid_wake" = "$(workspace_sha "$WORKSPACE")" ] \
  && record_pass 'invalid wake rejection leaves journal and evidence unchanged' \
  || record_fail 'invalid wake rejection leaves journal and evidence unchanged'
WAKE_EVIDENCE="$TEST_ROOT/valid-wake.md"
printf 'Wake evidence: The approved dependent slice consumes the parked interface.\n' >"$WAKE_EVIDENCE"
expect_success 'wake transition is accepted before the dependent slice is claimed' \
  "$FINDING_STATE" "$PLAN" transition "$wake_id" REPORTED "$WAKE_EVIDENCE"
[ "$(awk -F '\t' '$4 == "slice-2-implementer" && $5 == "CLAIM" { count++ } END { print count + 0 }' "$WORKSPACE/workflow-v1/events.tsv")" = 0 ] \
  && record_pass 'dependent slice remains unclaimed through the wake transition' \
  || record_fail 'dependent slice remains unclaimed through the wake transition'
next_output=$("$WORKFLOW_STATE" "$PLAN" next)
[ "$(printf '%s\n' "$next_output" | sed -n 's/^Ready obligation: //p')" = "finding-$wake_id-dispose" ] \
  && record_pass 'wake requires re-adjudication before the dependent slice resumes' \
  || record_fail 'wake requires re-adjudication before the dependent slice resumes'

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
complete_obligation slice-1-review task-reviewer
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
if grep -lq $'blocking-boundary\tslice-1-architect' "$WORKSPACE"/workflow-v1/events/*/metadata.tsv; then
  record_pass 'BLOCKED metadata records the dependency boundary'
else
  record_fail 'BLOCKED metadata records the dependency boundary'
fi
"$WORKFLOW_STATE" "$PLAN" status >/dev/null
blocked_boundary_status=$(awk -F '\t' '$1 == "slice-1-architect" { print $2 }' "$WORKSPACE/workflow-v1/projections/status.tsv")
[ "$blocked_boundary_status" = PENDING ] \
  && record_pass 'only the recorded static boundary is blocked' \
  || record_fail 'only the recorded static boundary is blocked'
next_output=$("$WORKFLOW_STATE" "$PLAN" next)
[ "$(printf '%s\n' "$next_output" | sed -n 's/^Ready obligation: //p')" = "finding-$second_ready_id-dispose" ] \
  && record_pass 'unrelated ready work is selected before the BLOCKED wake' \
  || record_fail 'unrelated ready work is selected before the BLOCKED wake'

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

assert_next() {
  local label=$1 expected=$2
  "$WORKFLOW_STATE" "$PLAN" next >"$OUT" 2>&1 || true
  expect_contains "$label" "$OUT" "$expected"
}

assert_status() {
  local label=$1 expected=$2
  "$WORKFLOW_STATE" "$PLAN" status >/dev/null 2>&1 || true
  cp "$WORKSPACE/workflow-v1/projections/status.tsv" "$OUT"
  expect_contains "$label" "$OUT" "$expected"
}

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
claim finding-GDD-F0001-repair-result fixer-max
"$FINDING_STATE" "$PLAN" repair-result GDD-F0001 "$FIXER_REPORT"
assert_next 'repair-result frees the review for re-review' slice-1-review
claim slice-1-review re-reviewer
write_role_report "$REVIEW" 0 PASS
"$FINDING_STATE" "$PLAN" report 1 Re-reviewer "$REVIEW" "$EMPTY_DIR"
assert_next 'a re-review with an open owned finding accepts as FAIL' finding-GDD-F0001-repair-finish-1
claim finding-GDD-F0001-repair-finish-1 controller
UNRELATED_REVIEW="$TEST_ROOT/review-round-unrelated.md"
printf 'unrelated review evidence\n' >"$UNRELATED_REVIEW"
write_repair_finish "$FINISH" 1 fixer-1 VERIFIED "$UNRELATED_REVIEW"
expect_failure 'a re-review repair-finish rejects unrelated evidence' \
  "$FINDING_STATE" "$PLAN" repair-finish GDD-F0001 "$FINISH"
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
  claim finding-GDD-F0001-repair-result fixer-max
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
claim finding-GDD-F0001-repair-result fixer-max
"$FINDING_STATE" "$PLAN" repair-result GDD-F0001 "$FIXER_REPORT"
"$FINDING_STATE" "$PLAN" guard 1 verifying-hardener
expect_failure 'a downstream finding permits only the next worker' \
  "$FINDING_STATE" "$PLAN" guard 1 verifying-qa
complete_obligation slice-1-architect architect
assert_next 'the Architect PASS readies the downstream finish' finding-GDD-F0001-repair-finish-1
claim finding-GDD-F0001-repair-finish-1 controller
UNRELATED_DOWNSTREAM="$TEST_ROOT/downstream-round-unrelated.md"
printf 'unrelated downstream evidence\n' >"$UNRELATED_DOWNSTREAM"
write_repair_finish "$FINISH" 1 fixer-1 VERIFIED "$UNRELATED_DOWNSTREAM"
expect_failure 'a downstream repair-finish rejects unrelated evidence' \
  "$FINDING_STATE" "$PLAN" repair-finish GDD-F0001 "$FINISH"
write_repair_finish "$FINISH" 1 fixer-1 VERIFIED "$LAST_ROLE_REPORT"
"$FINDING_STATE" "$PLAN" repair-finish GDD-F0001 "$FINISH"
claim finding-GDD-F0001-resolve controller
write_resolved "$RULING" "$FINISH"
"$FINDING_STATE" "$PLAN" transition GDD-F0001 RESOLVED "$RULING"

make_round_fixture hardener-executor
complete_obligation slice-1-implementer implementer
complete_obligation slice-1-review task-reviewer
complete_obligation slice-1-cleaner cleaner
complete_obligation slice-1-architect architect
claim slice-1-hardener hardener
write_finding "$FINDINGS_DIR/1.md" Hardener Critical 'missing mutation guard'
write_role_report "$ROLE_REPORT" 1 VERIFIED
"$FINDING_STATE" "$PLAN" report 1 Hardener "$ROLE_REPORT" "$FINDINGS_DIR" >/dev/null
claim finding-GDD-F0001-dispose controller
write_repairing "$RULING" downstream
"$FINDING_STATE" "$PLAN" transition GDD-F0001 REPAIRING "$RULING"
claim finding-GDD-F0001-repair-start-1 controller
write_repair_start "$REPAIR" 1 hardener hardener-1 'add the mutation guard'
expect_failure 'a Hardener downstream repair-start rejects Executor: hardener' \
  "$FINDING_STATE" "$PLAN" repair-start GDD-F0001 "$REPAIR"

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
claim finding-GDD-F0001-repair-result fixer-max
"$FINDING_STATE" "$PLAN" repair-result GDD-F0001 "$FIXER_REPORT"
claim finding-GDD-F0002-repair-result fixer-max
"$FINDING_STATE" "$PLAN" repair-result GDD-F0002 "$FIXER_REPORT"
write_role_report "$REVIEW" 0 PASS
claim feature-branch-review branch-reviewer
"$FINDING_STATE" "$PLAN" report feature 'Branch Reviewer' "$REVIEW" "$EMPTY_DIR"
claim finding-GDD-F0001-repair-finish-1 controller
write_repair_finish "$FINISH" 1 fixer-1 VERIFIED "$REVIEW"
"$FINDING_STATE" "$PLAN" repair-finish GDD-F0001 "$FINISH"
claim feature-security-review security-reviewer
"$FINDING_STATE" "$PLAN" report feature 'Security Reviewer' "$REVIEW" "$EMPTY_DIR"
claim finding-GDD-F0002-repair-finish-1 controller
"$FINDING_STATE" "$PLAN" repair-finish GDD-F0002 "$FINISH"
claim finding-GDD-F0001-resolve controller
write_resolved "$RULING" "$FINISH"
"$FINDING_STATE" "$PLAN" transition GDD-F0001 RESOLVED "$RULING"
claim finding-GDD-F0002-resolve controller
"$FINDING_STATE" "$PLAN" transition GDD-F0002 RESOLVED "$RULING"
claim feature-branch-review branch-reviewer
"$FINDING_STATE" "$PLAN" report feature 'Branch Reviewer' "$REVIEW" "$EMPTY_DIR"
claim feature-security-review security-reviewer
"$FINDING_STATE" "$PLAN" report feature 'Security Reviewer' "$REVIEW" "$EMPTY_DIR"
assert_next 'both closing reviews PASS release the digest' feature-findings-digest
expect_failure 'a second feature round is not claimable' \
  "$WORKFLOW_STATE" "$PLAN" claim finding-GDD-F0002-repair-start-2 controller "$DISPATCH"

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
exit "$fail"
