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

write_ruling() {
  local output=$1 disposition=$2
  printf '%s\n' \
    "Disposition: $disposition" \
    'Ruling: The evidence does not justify an immediate repair.' \
    'Cost if wrong: A later role could rely on stale evidence.' \
    'Wake condition: New evidence contradicts this ruling.' \
    'Fable result: UNAVAILABLE: deterministic fixture' >"$output"
}

origin_actor() {
  case "$1" in
    Cleaner) printf cleaner ;;
    Architect) printf architect ;;
    'Security Reviewer') printf security-reviewer ;;
    Hardener) printf hardener ;;
    QA) printf qa ;;
    'Branch Reviewer') printf branch-reviewer ;;
  esac
}

make_fixture no-receipt
REPORT="$TEST_ROOT/no-receipt-report.md"
write_report "$REPORT" Cleaner
before=$(workspace_sha "$WORKSPACE")
expect_failure 'report requires an active lifecycle receipt' "$FINDING_STATE" "$PLAN" report 1 Cleaner "$REPORT"
[ "$before" = "$(workspace_sha "$WORKSPACE")" ] && record_pass 'unclaimed report leaves the journal unchanged' || record_fail 'unclaimed report leaves the journal unchanged'

for origin in Cleaner Architect 'Security Reviewer' Hardener QA; do
  slug=$(printf '%s' "$origin" | tr '[:upper:] ' '[:lower:]-')
  make_fixture "origin-$slug"
  REPORT="$TEST_ROOT/origin-$slug.md"
  write_report "$REPORT" "$origin"
  claim slice-1-implementer "$(origin_actor "$origin")"
  finding_id=$("$FINDING_STATE" "$PLAN" report 1 "$origin" "$REPORT")
  [ "$finding_id" = GDD-F0001 ] && record_pass "$origin receives an engine ID" || record_fail "$origin receives an engine ID"
  repeated_id=$("$FINDING_STATE" "$PLAN" report 1 "$origin" "$REPORT")
  [ "$repeated_id" = "$finding_id" ] && record_pass "$origin report retry is idempotent" || record_fail "$origin report retry is idempotent"
  status_output=$("$WORKFLOW_STATE" "$PLAN" status)
  printf '%s\n' "$status_output" | grep -qF 'Active claim: slice-1-implementer' && record_pass "$origin report preserves the role claim" || record_fail "$origin report preserves the role claim"
  printf '%s\n' "$status_output" | grep -qF 'finding-GDD-F0001-verify COMPLETE' && record_pass "$origin creates VERIFY_FINDING" || record_fail "$origin creates VERIFY_FINDING"
  printf '%s\n' "$status_output" | grep -qF 'finding-GDD-F0001-dispose READY' && record_pass "$origin creates DISPOSE_FINDING" || record_fail "$origin creates DISPOSE_FINDING"
  metadata="$WORKSPACE/workflow-v1/events/event-2/metadata.tsv"
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
  claim "$obligation" "$actor"
  expect_success "accept $obligation" "$WORKFLOW_STATE" "$PLAN" accept "$LAST_RECEIPT" PASS "$RESULT"
done
claim feature-branch-review branch-reviewer
BRANCH_REPORT="$TEST_ROOT/branch-report.md"
write_report "$BRANCH_REPORT" 'Branch Reviewer'
branch_id=$("$FINDING_STATE" "$PLAN" report feature 'Branch Reviewer' "$BRANCH_REPORT")
[ "$branch_id" = GDD-F0001 ] && record_pass 'Branch Reviewer receives an engine ID' || record_fail 'Branch Reviewer receives an engine ID'
expect_contains 'Branch Reviewer metadata records feature scope' "$WORKSPACE/workflow-v1/events/event-18/metadata.tsv" $'finding-scope\tfeature'

make_fixture supplement
INCOMPLETE="$TEST_ROOT/incomplete.md"
COMPLETE="$TEST_ROOT/complete.md"
write_report "$INCOMPLETE" Cleaner no
write_report "$COMPLETE" Cleaner
claim slice-1-implementer cleaner
incomplete_id=$("$FINDING_STATE" "$PLAN" report 1 Cleaner "$INCOMPLETE")
expect_success 'role result is accepted after incomplete report' "$WORKFLOW_STATE" "$PLAN" accept "$LAST_RECEIPT" PASS "$RESULT"
status_output=$("$WORKFLOW_STATE" "$PLAN" status)
printf '%s\n' "$status_output" | grep -qF "finding-$incomplete_id-supplement READY" && record_pass 'incomplete report creates SUPPLEMENT_FINDING' || record_fail 'incomplete report creates SUPPLEMENT_FINDING'
printf '%s\n' "$status_output" | grep -qF "finding-$incomplete_id-dispose PENDING" && record_pass 'incomplete report blocks disposition' || record_fail 'incomplete report blocks disposition'
claim "finding-$incomplete_id-supplement" controller
expect_success 'supplement accepts the complete report' "$FINDING_STATE" "$PLAN" supplement "$incomplete_id" "$COMPLETE"
claim "finding-$incomplete_id-dispose" controller
RULING="$TEST_ROOT/dismissed.md"
write_ruling "$RULING" DISMISSED
expect_success 'terminal disposition uses DISPOSE_FINDING' "$FINDING_STATE" "$PLAN" transition "$incomplete_id" DISMISSED "$RULING"
for obligation_actor in \
  'slice-1-cleaner cleaner' \
  'slice-1-architect architect' \
  'slice-1-security security-reviewer' \
  'slice-1-hardener hardener' \
  'slice-1-qa qa' \
  'slice-1-final-suite controller' \
  'slice-1-verified controller' \
  'feature-branch-review branch-reviewer'; do
  obligation=${obligation_actor% *}
  actor=${obligation_actor##* }
  claim "$obligation" "$actor"
  expect_success "accept $obligation" "$WORKFLOW_STATE" "$PLAN" accept "$LAST_RECEIPT" PASS "$RESULT"
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
  claim slice-1-implementer "$(origin_actor "$mandatory_origin")"
  mandatory_id=$("$FINDING_STATE" "$PLAN" report 1 "$mandatory_origin" "$REPORT")
  expect_success "$mandatory_origin source result is accepted" "$WORKFLOW_STATE" "$PLAN" accept "$LAST_RECEIPT" PASS "$RESULT"
  claim "finding-$mandatory_id-dispose" controller
  write_ruling "$RULING" DISMISSED
  expect_success "$mandatory_origin finding can be dismissed" "$FINDING_STATE" "$PLAN" transition "$mandatory_id" DISMISSED "$RULING"
  mandatory_status=$(awk -F '\t' -v id="slice-1-$slug" '$1 == id { print $2 }' "$WORKSPACE/workflow-v1/projections/status.tsv")
  [ "$mandatory_status" != COMPLETE ] && record_pass "$mandatory_origin obligation remains unsatisfied" || record_fail "$mandatory_origin obligation remains unsatisfied"
done

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
