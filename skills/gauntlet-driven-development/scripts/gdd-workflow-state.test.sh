#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

pass=0
fail=0
status=0
output=''

record_pass() {
  pass=$((pass + 1))
  printf 'PASS  %s\n' "$1"
}

record_fail() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
}

run_workflow() {
  output=$("$WORKFLOW" "$@" 2>&1)
  status=$?
}

run_interrupted_workflow() {
  output=$(GDD_WORKFLOW_TEST_INTERRUPT_AFTER_EVIDENCE=1 "$WORKFLOW" "$@" 2>&1)
  status=$?
}

run_publication_interrupted_workflow() {
  output=$(GDD_WORKFLOW_TEST_INTERRUPT_DURING_EVIDENCE_PUBLICATION=1 "$WORKFLOW" "$@" 2>&1)
  status=$?
}

run_projection_interrupted_workflow() {
  output=$(GDD_WORKFLOW_TEST_FAIL_PROJECTION=1 "$WORKFLOW" "$@" 2>&1)
  status=$?
}

run_projection_boundary_interrupted_workflow() {
  boundary=$1
  shift
  output=$(GDD_WORKFLOW_TEST_INTERRUPT_PROJECTION_AT="$boundary" "$WORKFLOW" "$@" 2>&1)
  status=$?
}

assert_status() {
  expected=$1
  if [ "$status" -eq "$expected" ]; then
    record_pass "exit status is $expected"
  else
    record_fail "exit status is $expected (got $status)"
    printf '      output: %s\n' "$output"
  fi
}

assert_output_contains() {
  expected=$1
  if printf '%s\n' "$output" | grep -qF -- "$expected"; then
    record_pass "output contains $expected"
  else
    record_fail "output contains $expected"
    printf '      output: %s\n' "$output"
  fi
}

assert_file() {
  file=$1
  if [ -f "$file" ]; then
    record_pass "file exists: $file"
  else
    record_fail "file exists: $file"
  fi
}

assert_file_contains() {
  file=$1
  expected=$2
  if grep -qF -- "$expected" "$file"; then
    record_pass "file contains $expected: $file"
  else
    record_fail "file contains $expected: $file"
  fi
}

assert_not_exists() {
  path=$1
  if [ ! -e "$path" ]; then
    record_pass "path does not exist: $path"
  else
    record_fail "path does not exist: $path"
  fi
}

assert_equals() {
  expected=$1
  actual=$2
  if [ "$expected" = "$actual" ]; then
    record_pass 'values match'
  else
    record_fail "values match (expected $expected, got $actual)"
  fi
}

assert_file_count() {
  directory=$1
  expected_count=$2
  actual_count=$(find "$directory" -type f | wc -l | tr -d ' ')
  assert_equals "$expected_count" "$actual_count"
}

assert_matches() {
  actual=$1
  pattern=$2
  if printf '%s\n' "$actual" | grep -Eq -- "$pattern"; then
    record_pass "value matches $pattern"
  else
    record_fail "value matches $pattern (got $actual)"
  fi
}

extract_field() {
  field_name=$1
  printf '%s\n' "$output" | awk -F ': ' -v expected="$field_name" '$1 == expected { print $2; exit }'
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    sha256sum "$1" | awk '{ print $1 }'
  fi
}

journal_and_evidence_sha() {
  local journal=$1
  {
    sha256_file "$journal/events.tsv"
    find "$journal/events" -type f -print0 | sort -z | xargs -0 shasum -a 256
  } | shasum -a 256 | awk '{ print $1 }'
}

run_grouped_workflow() {
  local findings_dir=$1
  shift
  output=$(GDD_FINDINGS_DIR="$findings_dir" "$WORKFLOW" "$@" 2>&1)
  status=$?
}

event_hash() {
  {
    printf '%s' "$1"
    shift
    for field_value in "$@"; do
      printf '\t%s' "$field_value"
    done
  } | shasum -a 256 | awk '{ print $1 }'
}

write_event_evidence() {
  workflow_root=$1
  evidence_path=$2
  evidence_content=$3
  mkdir -p "$(dirname "$workflow_root/$evidence_path")"
  printf '%s\n' "$evidence_content" >"$workflow_root/$evidence_path"
}

append_event() {
  workflow_root=$1
  sequence=$2
  revision=$3
  event_id=$4
  obligation_id=$5
  kind=$6
  actor=$7
  receipt=$8
  evidence_path=$9
  evidence_digest=${10}
  previous_hash=${11}
  event_digest=$(event_hash "$sequence" "$revision" "$event_id" "$obligation_id" "$kind" "$actor" "$receipt" "$evidence_path" "$evidence_digest" "$previous_hash")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$sequence" "$revision" "$event_id" "$obligation_id" "$kind" "$actor" "$receipt" "$evidence_path" "$evidence_digest" "$previous_hash" "$event_digest" \
    >>"$workflow_root/events.tsv"
}

initialize_journal_fixture() {
  fixture_name=$1
  make_fixture "$fixture_name"
  run_workflow "$PLAN_FILE" init
  assert_status 0
}

fixture_hash() {
  fixture_root=$1
  find "$fixture_root" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{ print $1 }'
}

projection_hash() {
  projection_workspace=$1
  projection_tasks=$2
  {
    printf 'tasks\t%s\n' "$(sha256_file "$projection_tasks")"
    printf 'ledger\t%s\n' "$(sha256_file "$projection_workspace/ledger.tsv")"
    printf 'findings-tsv\t%s\n' "$(sha256_file "$projection_workspace/findings.tsv")"
    find "$projection_workspace/findings" -type f -print | sort | while IFS= read -r projection_file; do
      printf 'finding\t%s\t%s\n' "${projection_file#"$projection_workspace/findings/"}" "$(sha256_file "$projection_file")"
    done
    printf 'status\t%s\n' "$(sha256_file "$projection_workspace/workflow-v1/projections/status.tsv")"
  } | shasum -a 256 | awk '{ print $1 }'
}

write_valid_tasks() {
  tasks_file=$1
  cat >"$tasks_file" <<'EOF'
## 1. Initialize the obligation journal
**Slice state:** [ ] QUEUED

- [ ] 1.1 Implement the journal command
- [ ] 1.V **Slice verification gate**

## 2. Record lifecycle claims
**Slice state:** [ ] QUEUED

- [ ] 2.1 Record claim events
- [ ] 2.V **Slice verification gate**
EOF
}

make_fixture() {
  fixture_name=$1
  REPO="$TEST_ROOT/$fixture_name/repo"
  CHANGE="$REPO/openspec/changes/$fixture_name"
  PLAN_FILE="$CHANGE/plan.md"
  WORKSPACE="$REPO/.superpowers/gdd/$fixture_name"
  mkdir -p "$CHANGE"
  git -C "$REPO" init -q
  git -C "$REPO" config user.name 'Test Bot'
  git -C "$REPO" config user.email 'test@example.com'
  printf '%s\n' "# $fixture_name" >"$PLAN_FILE"
  write_valid_tasks "$CHANGE/tasks.md"
  printf '%s\n' 'fixture' >"$REPO/README.md"
  git -C "$REPO" add README.md openspec
  git -C "$REPO" commit -qm 'chore: fixture'
}

RUNTIME_ROOT="$TEST_ROOT/runtime"
mkdir -p "$RUNTIME_ROOT/scripts"
cp "$SOURCE_DIR/gdd-workspace" "$RUNTIME_ROOT/scripts/gdd-workspace"
cp "$SOURCE_DIR/../finding-policy.md" "$RUNTIME_ROOT/finding-policy.md"
if [ -f "$SOURCE_DIR/gdd-workflow-state" ]; then
  cp "$SOURCE_DIR/gdd-workflow-state" "$RUNTIME_ROOT/scripts/gdd-workflow-state"
  chmod +x "$RUNTIME_ROOT/scripts/gdd-workflow-state"
fi
cp "$SOURCE_DIR/gdd-finding-state" "$RUNTIME_ROOT/scripts/gdd-finding-state"
chmod +x "$RUNTIME_ROOT/scripts/gdd-finding-state"
WORKFLOW="$RUNTIME_ROOT/scripts/gdd-workflow-state"
FINDING_STATE="$RUNTIME_ROOT/scripts/gdd-finding-state"

write_role_result() {
  local output_file=$1
  local status_value=$2
  printf 'Status: %s\nFinding count: 0\n' "$status_value" >"$output_file"
}

setup_claimed_hardener() {
  local fixture_name=$1
  local role_obligation role_actor role_result
  initialize_journal_fixture "$fixture_name"
  JOURNAL="$WORKSPACE/workflow-v1"
  DISPATCH_FILE="$REPO/dispatch.md"
  RESULT_FILE="$REPO/result.md"
  FINDINGS_DIR="$REPO/zero-findings"
  mkdir -p "$FINDINGS_DIR"
  printf '%s\n' 'Dispatch: advance the lifecycle.' >"$DISPATCH_FILE"
  printf '%s\n' 'Status: DONE' >"$RESULT_FILE"

  run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
  assert_status 0
  lifecycle_receipt=$(extract_field 'Receipt')
  run_workflow "$PLAN_FILE" accept "$lifecycle_receipt" PASS "$RESULT_FILE"
  assert_status 0

  for role_obligation in slice-1-review slice-1-cleaner slice-1-architect; do
    case "$role_obligation" in
      slice-1-review) role_actor=task-reviewer ;;
      slice-1-cleaner) role_actor=cleaner ;;
      slice-1-architect) role_actor=architect ;;
    esac
    role_result="$REPO/$role_obligation.md"
    write_role_result "$role_result" PASS
    run_workflow "$PLAN_FILE" claim "$role_obligation" "$role_actor" "$DISPATCH_FILE"
    assert_status 0
    run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active "$role_obligation" PASS "$role_result"
    assert_status 0
  done

  run_workflow "$PLAN_FILE" claim slice-1-hardener hardener "$DISPATCH_FILE"
  assert_status 0
}

accept_review_for_cleaner() {
  local review_findings="$REPO/zero-review-findings"
  local review_result="$REPO/review-result.md"
  mkdir -p "$review_findings"
  write_role_result "$review_result" PASS
  run_workflow "$PLAN_FILE" claim slice-1-review task-reviewer "$DISPATCH_FILE"
  assert_status 0
  run_grouped_workflow "$review_findings" "$PLAN_FILE" accept-active slice-1-review PASS "$review_result"
  assert_status 0
}

setup_claimed_qa() {
  local fixture_name=$1
  local hardener_result
  setup_claimed_hardener "$fixture_name"
  hardener_result="$REPO/hardener-result.md"
  write_role_result "$hardener_result" VERIFIED
  run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-hardener PASS "$hardener_result"
  assert_status 0
  run_workflow "$PLAN_FILE" claim slice-1-qa qa "$DISPATCH_FILE"
  assert_status 0
}

assert_admission_rejected_unchanged() {
  local case_name=$1
  local expected_output=$2
  local before_snapshot=$3
  local after_snapshot
  if [ "$status" -eq 1 ]; then
    record_pass "$case_name rejects the result"
  else
    record_fail "$case_name rejects the result (got $status)"
    printf '      output: %s\n' "$output"
  fi
  if printf '%s\n' "$output" | grep -qF -- "$expected_output"; then
    record_pass "$case_name reports the binding evidence failure"
  else
    record_fail "$case_name reports the binding evidence failure"
    printf '      output: %s\n' "$output"
  fi
  after_snapshot=$(journal_and_evidence_sha "$JOURNAL")
  assert_equals "$before_snapshot" "$after_snapshot"
}

assert_completion_mutation_rejected() {
  local mutation_name=$1

  run_workflow "$PLAN_FILE" status
  if [ "$status" -eq 1 ] && printf '%s\n' "$output" | grep -qF INVALID; then
    record_pass "$mutation_name produces INVALID"
  elif [ "$status" -eq 0 ] && printf '%s\n' "$output" | grep -qF 'Completion eligible: no'; then
    record_pass "$mutation_name leaves completion ineligible"
  else
    record_fail "$mutation_name rejects completed workflow state"
    printf '      output: %s\n' "$output"
  fi
}

make_fixture 'journal-init'

# Break caught: omitting v1 workspace initialization leaves the lifecycle without durable state.
run_workflow "$PLAN_FILE" init
assert_status 0
assert_file "$WORKSPACE/workflow-v1/format-version"
assert_file_contains "$WORKSPACE/workflow-v1/format-version" '2'
assert_file "$WORKSPACE/workflow-v1/obligations.tsv"
assert_file "$WORKSPACE/workflow-v1/events.tsv"
assert_output_contains 'Workflow status: ACTIVE'

# Break caught: a reducer that never marks the first lifecycle role ready cannot start a fresh plan.
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Ready obligation: slice-1-implementer'
assert_output_contains 'Completion eligible: no'
assert_file_contains "$WORKSPACE/workflow-v1/obligations.tsv" $'slice-2-implementer\tslice-2\timplementer\tslice-1-verified'
assert_file_contains "$WORKSPACE/workflow-v1/obligations.tsv" $'feature-branch-review\tfeature\tbranch-review\tslice-1-verified,slice-2-verified'
assert_file_contains "$WORKSPACE/workflow-v1/obligations.tsv" $'slice-1-review\tslice-1\treview\tslice-1-implementer\tPASS,FAIL\tslice\treview-report'
assert_file_contains "$WORKSPACE/workflow-v1/obligations.tsv" $'slice-1-cleaner\tslice-1\tcleaner\tslice-1-review'
assert_file_contains "$WORKSPACE/workflow-v1/obligations.tsv" $'slice-1-hardener\tslice-1\thardener\tslice-1-architect'
assert_file_contains "$WORKSPACE/workflow-v1/obligations.tsv" $'feature-security-review\tfeature\tsecurity-review\tslice-1-verified,slice-2-verified\tPASS,FAIL\tfeature\tsecurity-review-report'
assert_file_contains "$WORKSPACE/workflow-v1/obligations.tsv" $'feature-findings-digest\tfeature\tfindings-digest\tfeature-branch-review,feature-security-review'
run_workflow "$PLAN_FILE" format-version
assert_status 0
assert_output_contains '2'
if grep -q 'slice-1-security' "$WORKSPACE/workflow-v1/obligations.tsv"; then
  record_fail 'no per-slice security obligation is compiled'
else
  record_pass 'no per-slice security obligation is compiled'
fi

initialize_journal_fixture 'valid-journal'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/claim.md' 'implementer claim evidence'
claim_digest=$(sha256_file "$JOURNAL/events/claim.md")
append_event "$JOURNAL" 1 1 event-1 slice-1-implementer CLAIM implementer receipt-1 events/claim.md "$claim_digest" -

# Break caught: a reducer that ignores valid journal events loses the active lifecycle claim.
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Active claim: slice-1-implementer'

initialize_journal_fixture 'fs-receipt'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/claim.md' 'field separator receipt evidence'
claim_digest=$(sha256_file "$JOURNAL/events/claim.md")
field_separator_receipt=$'receipt-\034-value'
append_event "$JOURNAL" 1 1 event-1 slice-1-implementer CLAIM implementer "$field_separator_receipt" events/claim.md "$claim_digest" -

# Break caught: a permitted ASCII FS byte in a receipt must not corrupt TSV fields.
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Active claim: slice-1-implementer'

initialize_journal_fixture 'empty-claim-receipt'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/claim.md' 'empty receipt evidence'
claim_digest=$(sha256_file "$JOURNAL/events/claim.md")
append_event "$JOURNAL" 1 1 event-1 slice-1-implementer CLAIM implementer '' events/claim.md "$claim_digest" -

# Break caught: an empty claim receipt does not hold the serialized workflow lock.
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains INVALID
assert_output_contains 'claim receipt is empty at sequence 1'

initialize_journal_fixture 'sequence-gap'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/claim.md' 'sequence gap evidence'
claim_digest=$(sha256_file "$JOURNAL/events/claim.md")
append_event "$JOURNAL" 2 2 event-2 slice-1-implementer CLAIM implementer receipt-2 events/claim.md "$claim_digest" -

# Break caught: accepting a journal with a skipped sequence hides a missing lifecycle event.
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains INVALID
assert_output_contains 'event sequence gap at 2'
run_workflow "$PLAN_FILE" next
assert_status 1
assert_output_contains INVALID

initialize_journal_fixture 'revision-gap'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/claim.md' 'revision gap evidence'
claim_digest=$(sha256_file "$JOURNAL/events/claim.md")
append_event "$JOURNAL" 1 2 event-1 slice-1-implementer CLAIM implementer receipt-1 events/claim.md "$claim_digest" -

# Break caught: accepting a skipped revision prevents deterministic replay.
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains INVALID
assert_output_contains 'event revision gap at 2'

initialize_journal_fixture 'unknown-kind'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/claim.md' 'unknown kind evidence'
claim_digest=$(sha256_file "$JOURNAL/events/claim.md")
append_event "$JOURNAL" 1 1 event-1 slice-1-implementer SURPRISE implementer receipt-1 events/claim.md "$claim_digest" -

# Break caught: an unknown event kind must not change lifecycle state.
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains INVALID
assert_output_contains 'unknown event kind: SURPRISE'

initialize_journal_fixture 'broken-hash'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/claim.md' 'broken hash evidence'
claim_digest=$(sha256_file "$JOURNAL/events/claim.md")
append_event "$JOURNAL" 1 1 event-1 slice-1-implementer CLAIM implementer receipt-1 events/claim.md "$claim_digest" -
awk 'BEGIN { FS = OFS = "\t" } NR == 1 { print; next } { $11 = "broken-hash"; print }' "$JOURNAL/events.tsv" >"$JOURNAL/events.tampered.tsv"
mv "$JOURNAL/events.tampered.tsv" "$JOURNAL/events.tsv"

# Break caught: a tampered event hash must invalidate the journal before projection.
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains INVALID
assert_output_contains 'broken event hash at sequence 1'

initialize_journal_fixture 'missing-evidence'
JOURNAL="$WORKSPACE/workflow-v1"
missing_digest='0000000000000000000000000000000000000000000000000000000000000000'
append_event "$JOURNAL" 1 1 event-1 slice-1-implementer CLAIM implementer receipt-1 events/missing.md "$missing_digest" -

# Break caught: an event without its evidence must never become an active claim.
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains INVALID
assert_output_contains 'event evidence is missing: events/missing.md'

initialize_journal_fixture 'digest-mismatch'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/claim.md' 'digest mismatch evidence'
mismatched_digest='0000000000000000000000000000000000000000000000000000000000000000'
append_event "$JOURNAL" 1 1 event-1 slice-1-implementer CLAIM implementer receipt-1 events/claim.md "$mismatched_digest" -

# Break caught: an evidence digest that does not match its file must invalidate the event.
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains INVALID
assert_output_contains 'event evidence digest does not match: events/claim.md'

initialize_journal_fixture 'concurrent-claims'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/claim-one.md' 'first claim evidence'
write_event_evidence "$JOURNAL" 'events/claim-two.md' 'second claim evidence'
first_claim_digest=$(sha256_file "$JOURNAL/events/claim-one.md")
second_claim_digest=$(sha256_file "$JOURNAL/events/claim-two.md")
append_event "$JOURNAL" 1 1 event-1 slice-1-implementer CLAIM implementer receipt-1 events/claim-one.md "$first_claim_digest" -
first_event_hash=$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')
append_event "$JOURNAL" 2 2 event-2 slice-1-cleaner CLAIM cleaner receipt-2 events/claim-two.md "$second_claim_digest" "$first_event_hash"

# Break caught: a second live receipt allows two lifecycle roles to run at once.
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains INVALID
assert_output_contains 'overlapping claim at sequence 2'

initialize_journal_fixture 'unknown-version'
JOURNAL="$WORKSPACE/workflow-v1"
printf '%s\n' 1 >"$JOURNAL/format-version"

# Break caught: an unknown journal version must be rejected by the reducer, not a preflight shortcut.
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains INVALID
assert_output_contains 'workflow format version is unknown: 1'

make_fixture 'legacy-refusal'
mkdir -p "$WORKSPACE/findings"
printf '%s\n' 'legacy ledger' >"$WORKSPACE/ledger.tsv"
printf '%s\n' 'legacy findings' >"$WORKSPACE/findings.tsv"
printf '%s\n' '*' >"$REPO/.superpowers/gdd/.gitignore"
before_hash=$(fixture_hash "$TEST_ROOT/legacy-refusal")

# Break caught: initialization that mixes the old mutable workspace with v1 destroys the restart boundary.
run_workflow "$PLAN_FILE" init
assert_status 1
assert_output_contains 'legacy GDD workspace must restart from approved artifacts'
after_hash=$(fixture_hash "$TEST_ROOT/legacy-refusal")
assert_equals "$before_hash" "$after_hash"
assert_not_exists "$WORKSPACE/workflow-v1"

make_fixture 'missing-tasks'
rm "$CHANGE/tasks.md"
run_workflow "$PLAN_FILE" init
assert_status 1
assert_output_contains 'no tasks.md beside plan'

make_fixture 'malformed-slice'
printf '%s\n' \
  '## 1. Broken metadata' \
  '**Slice state:** [ ] QUEUED' \
  '- [ ] 1.1 Implement the journal command' >"$CHANGE/tasks.md"
run_workflow "$PLAN_FILE" init
assert_status 1
assert_output_contains 'slice 1 must contain exactly one Slice verification gate'

make_fixture 'duplicate-slice'
printf '%s\n' \
  '## 1. First slice' \
  '**Slice state:** [ ] QUEUED' \
  '- [ ] 1.1 Implement one' \
  '- [ ] 1.V **Slice verification gate**' \
  '' \
  '## 1. Duplicate slice' \
  '**Slice state:** [ ] QUEUED' \
  '- [ ] 1.1 Implement two' \
  '- [ ] 1.V **Slice verification gate**' >"$CHANGE/tasks.md"
run_workflow "$PLAN_FILE" init
assert_status 1
assert_output_contains 'duplicate slice number: 1'

make_fixture 'missing-policy'
rm "$RUNTIME_ROOT/finding-policy.md"
run_workflow "$PLAN_FILE" init
assert_status 1
assert_output_contains 'finding policy is missing'
cp "$SOURCE_DIR/../finding-policy.md" "$RUNTIME_ROOT/finding-policy.md"

make_fixture 'repeat-init'
run_workflow "$PLAN_FILE" init
assert_status 0
before_hash=$(fixture_hash "$TEST_ROOT/repeat-init")
run_workflow "$PLAN_FILE" init
assert_status 0
after_hash=$(fixture_hash "$TEST_ROOT/repeat-init")
assert_equals "$before_hash" "$after_hash"

initialize_journal_fixture 'action-receipts'
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/result.md"
CONFLICTING_RESULT_FILE="$REPO/conflicting-result.md"
SECOND_CONFLICTING_RESULT_FILE="$REPO/second-conflicting-result.md"
RELEASE_FILE="$REPO/release.md"
printf '%s\n' 'Dispatch: implement slice one.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: DONE' >"$RESULT_FILE"
printf '%s\n' 'Status: FAIL' >"$CONFLICTING_RESULT_FILE"
printf '%s\n' 'Status: conflicting retry' >"$SECOND_CONFLICTING_RESULT_FILE"
printf '%s\n' 'Status: DISPATCH_FAILED' >"$RELEASE_FILE"

# Break caught: permitting an unrecorded action lets a controller issue work without a durable receipt.
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
receipt=$(extract_field 'Receipt')
assert_matches "$receipt" '^GDD-R[0-9a-f]{64}$'

# Break caught: issuing another ready obligation while work is claimed duplicates serialized lifecycle work.
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains 'Resume claim: slice-1-implementer'
assert_output_contains "Receipt: $receipt"
run_workflow "$PLAN_FILE" claim slice-1-cleaner cleaner "$DISPATCH_FILE"
assert_status 1
assert_output_contains 'one action is already claimed'

# Break caught: an unapproved result kind must not complete the claimed obligation.
run_workflow "$PLAN_FILE" accept "$receipt" UNKNOWN "$RESULT_FILE"
assert_status 1
assert_output_contains 'is not allowed'

# Break caught: a receipt from another action must not consume the active claim.
run_workflow "$PLAN_FILE" accept GDD-R0000000000000000000000000000000000000000000000000000000000000000 PASS "$RESULT_FILE"
assert_status 1
assert_output_contains 'does not match the active claim'

# Break caught: a valid receipt and evidence must append exactly one accepted result.
run_workflow "$PLAN_FILE" accept "$receipt" PASS "$RESULT_FILE"
assert_status 0
accepted_event_id=$(extract_field 'Event ID')
assert_matches "$accepted_event_id" '^event-[0-9]+$'

# Break caught: a controller retry must return the already accepted event instead of appending another result.
run_workflow "$PLAN_FILE" accept "$receipt" PASS "$RESULT_FILE"
assert_status 0
assert_output_contains "Event ID: $accepted_event_id"

# Break caught: a later result with a consumed receipt must be retained as a rejection and never change state.
run_workflow "$PLAN_FILE" accept "$receipt" FAIL "$CONFLICTING_RESULT_FILE"
assert_status 1
assert_output_contains "Accepted event ID: $accepted_event_id"
run_workflow "$PLAN_FILE" accept "$receipt" PASS "$SECOND_CONFLICTING_RESULT_FILE"
assert_status 1
assert_output_contains "Accepted event ID: $accepted_event_id"
assert_file_count "$WORKSPACE/workflow-v1/rejections" 2

# Break caught: changing accepted evidence after publication must invalidate the authoritative journal.
printf '%s\n' 'Status: altered after acceptance' >"$WORKSPACE/workflow-v1/events/$accepted_event_id/result"
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains 'event evidence digest does not match'

initialize_journal_fixture 'dispatch-release'
DISPATCH_FILE="$REPO/dispatch.md"
RELEASE_FILE="$REPO/release.md"
printf '%s\n' 'Dispatch: retry slice one.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: DISPATCH_FAILED' >"$RELEASE_FILE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
release_receipt=$(extract_field 'Receipt')

# Break caught: arbitrary release evidence could silently discard a dispatched action.
printf '%s\n' 'Status: PASS' >"$RELEASE_FILE"
run_workflow "$PLAN_FILE" release "$release_receipt" "$RELEASE_FILE"
assert_status 1
assert_output_contains 'DISPATCH_FAILED'
printf '%s\n' 'Status: DISPATCH_FAILED' >"$RELEASE_FILE"
run_workflow "$PLAN_FILE" release "$release_receipt" "$RELEASE_FILE"
assert_status 0
released_event_id=$(extract_field 'Event ID')
run_workflow "$PLAN_FILE" release "$release_receipt" "$RELEASE_FILE"
assert_status 0
assert_output_contains "Event ID: $released_event_id"
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains 'slice-1-implementer'

initialize_journal_fixture 'supporting-evidence-integrity'
JOURNAL="$WORKSPACE/workflow-v1"
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/result.md"
SUPPORTING_ONE="$REPO/supporting-one.md"
SUPPORTING_TWO="$REPO/supporting-two.md"
printf '%s\n' 'Dispatch: retain supporting evidence.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: DONE' >"$RESULT_FILE"
printf '%s\n' 'supporting evidence one' >"$SUPPORTING_ONE"
printf '%s\n' 'supporting evidence two' >"$SUPPORTING_TWO"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
supporting_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$supporting_receipt" PASS "$RESULT_FILE" "$SUPPORTING_ONE" "$SUPPORTING_TWO"
assert_status 0
supporting_event_id=$(extract_field 'Event ID')
supporting_metadata="$JOURNAL/events/$supporting_event_id/metadata.tsv"
supporting_one_path="events/$supporting_event_id/supporting-1"
supporting_two_path="events/$supporting_event_id/supporting-2"
assert_file_contains "$supporting_metadata" $'supporting-evidence-1-path\t'"$supporting_one_path"
assert_file_contains "$supporting_metadata" $'supporting-evidence-1-sha256\t'"$(sha256_file "$SUPPORTING_ONE")"
assert_file_contains "$supporting_metadata" $'supporting-evidence-2-path\t'"$supporting_two_path"
assert_file_contains "$supporting_metadata" $'supporting-evidence-2-sha256\t'"$(sha256_file "$SUPPORTING_TWO")"
SUPPORTING_BASELINE="$TEST_ROOT/supporting-evidence-baseline"
cp -R "$JOURNAL" "$SUPPORTING_BASELINE"

# Break caught: deleting a replay or advisory attachment must invalidate the
# event whose hash covers the supporting-evidence manifest.
rm -f "$JOURNAL/$supporting_one_path"
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains 'supporting evidence is missing'

# Break caught: replacing a supporting copy without changing the journal must
# fail its accepted SHA-256 contract.
rm -rf "$JOURNAL"
cp -R "$SUPPORTING_BASELINE" "$JOURNAL"
printf '%s\n' 'replacement supporting evidence' >"$JOURNAL/$supporting_one_path"
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains 'supporting evidence digest does not match'

# Break caught: swapping two supporting copies must not preserve validity when
# the accepted order determines each deterministic path.
rm -rf "$JOURNAL"
cp -R "$SUPPORTING_BASELINE" "$JOURNAL"
cp "$JOURNAL/$supporting_one_path" "$JOURNAL/supporting-swap"
cp "$JOURNAL/$supporting_two_path" "$JOURNAL/$supporting_one_path"
cp "$JOURNAL/supporting-swap" "$JOURNAL/$supporting_two_path"
rm -f "$JOURNAL/supporting-swap"
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains 'supporting evidence digest does not match'

initialize_journal_fixture 'stale-claim-revision'
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/result.md"
printf '%s\n' 'Dispatch: stale revision check.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: DONE' >"$RESULT_FILE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
stale_receipt=$(extract_field 'Receipt')
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/invalidation.md' 'explicit invalidation changed the journal revision'
invalidation_digest=$(sha256_file "$JOURNAL/events/invalidation.md")
claim_event_hash=$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')
append_event "$JOURNAL" 2 2 event-2 slice-1-implementer EvidenceInvalidated implementer "$stale_receipt" events/invalidation.md "$invalidation_digest" "$claim_event_hash"

# Break caught: an acceptance against a claim revision superseded by another event must not consume the claim.
run_workflow "$PLAN_FILE" accept "$stale_receipt" PASS "$RESULT_FILE"
assert_status 1
assert_output_contains 'receipt claim revision is stale'

initialize_journal_fixture 'interrupted-transaction'
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: recover staged claim.' >"$DISPATCH_FILE"

# Break caught: a crash after publishing evidence but before the journal must be recovered on the next command.
run_interrupted_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 75
staged_transaction=$(find "$WORKSPACE/workflow-v1" -maxdepth 1 -type d -name '.stage.*' -print -quit)
assert_file "$staged_transaction/transaction-manifest.tsv"
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains 'Resume claim: slice-1-implementer'
assert_not_exists "$staged_transaction"

initialize_journal_fixture 'interrupted-recovery-init'
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: recover through init.' >"$DISPATCH_FILE"
run_interrupted_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 75
staged_transaction=$(find "$WORKSPACE/workflow-v1" -maxdepth 1 -type d -name '.stage.*' -print -quit)

# Break caught: repeated initialization must recover an interrupted existing workflow before projecting it.
run_workflow "$PLAN_FILE" init
assert_status 0
assert_output_contains 'Active claim: slice-1-implementer'
assert_not_exists "$staged_transaction"

initialize_journal_fixture 'interrupted-recovery-format'
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: recover through format version.' >"$DISPATCH_FILE"
run_interrupted_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 75
staged_transaction=$(find "$WORKSPACE/workflow-v1" -maxdepth 1 -type d -name '.stage.*' -print -quit)

# Break caught: format-version must not report a stale workflow while an interrupted transaction is pending.
run_workflow "$PLAN_FILE" format-version
assert_status 0
assert_output_contains '2'
assert_not_exists "$staged_transaction"
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains 'Resume claim: slice-1-implementer'

initialize_journal_fixture 'missing-event-directory'
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: remove copied evidence.' >"$DISPATCH_FILE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
rm -rf "$WORKSPACE/workflow-v1/events/event-1"

# Break caught: an event whose immutable evidence directory disappeared must invalidate the journal.
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains 'event evidence is missing'

initialize_journal_fixture 'accept-active-projection'
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/result.md"
printf '%s\n' 'Dispatch: accept through the compatibility adapter.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: DONE' >"$RESULT_FILE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0

# Break caught: accept-active must validate the exact currently claimed obligation.
run_workflow "$PLAN_FILE" accept-active slice-1-cleaner PASS "$RESULT_FILE"
assert_status 1
assert_output_contains 'active claim is slice-1-implementer'

# Break caught: a projection failure must not roll back the accepted journal event.
run_projection_interrupted_workflow "$PLAN_FILE" accept-active slice-1-implementer PASS "$RESULT_FILE"
assert_status 1
assert_output_contains 'journal accepted; projection rebuild is recoverable'
assert_file_contains "$WORKSPACE/workflow-v1/events.tsv" $'slice-1-implementer\tACCEPT'
run_workflow "$PLAN_FILE" status
assert_status 0
assert_file_contains "$CHANGE/tasks.md" '**Slice state:** [~] REVIEWING'

initialize_journal_fixture 'finding-side-event'
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/finding.md"
printf '%s\n' 'Dispatch: collect Cleaner findings.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: DONE' 'Origin role: Cleaner' >"$RESULT_FILE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
implementer_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$implementer_receipt" PASS "$RESULT_FILE"
assert_status 0
accept_review_for_cleaner
run_workflow "$PLAN_FILE" claim slice-1-cleaner cleaner "$DISPATCH_FILE"
assert_status 0
output=$(GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN=Cleaner GDD_REPORT_COMPLETE=no \
  "$WORKFLOW" "$PLAN_FILE" accept-active slice-1-cleaner FindingReported "$RESULT_FILE" 2>&1)
status=$?
assert_status 1
assert_output_contains 'lifecycle findings must use grouped role acceptance'
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Active claim: slice-1-cleaner'

initialize_journal_fixture 'finding-role-authority'
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/finding.md"
printf '%s\n' 'Dispatch: verify role-derived finding authority.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: DONE' 'Origin role: Architect' >"$RESULT_FILE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
implementer_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$implementer_receipt" PASS "$RESULT_FILE"
assert_status 0
accept_review_for_cleaner
run_workflow "$PLAN_FILE" claim slice-1-cleaner architect "$DISPATCH_FILE"
assert_status 0

# Break caught: actor text is audit identity and cannot authorize another lifecycle role's finding.
output=$(GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN=Architect GDD_REPORT_COMPLETE=no \
  "$WORKFLOW" "$PLAN_FILE" accept-active slice-1-cleaner FindingReported "$RESULT_FILE" 2>&1)
status=$?
assert_status 1
assert_output_contains 'lifecycle findings must use grouped role acceptance'
assert_equals 6 "$(wc -l <"$WORKSPACE/workflow-v1/events.tsv" | tr -d ' ')"

for projection_boundary in 1 2 3 4 5; do
  initialize_journal_fixture "projection-boundary-$projection_boundary"
  expected_projection_hash=$(projection_hash "$WORKSPACE" "$CHANGE/tasks.md")
  sed 's/\*\*Slice state:\*\* \[ \] QUEUED/**Slice state:** [~] IMPLEMENTING/' "$CHANGE/tasks.md" >"$CHANGE/tasks.stale.md"
  mv "$CHANGE/tasks.stale.md" "$CHANGE/tasks.md"
  printf 'stale ledger\n' >"$WORKSPACE/ledger.tsv"
  printf 'stale findings\n' >"$WORKSPACE/findings.tsv"
  printf 'stale finding directory\n' >"$WORKSPACE/findings/stale"
  printf 'stale status\n' >"$WORKSPACE/workflow-v1/projections/status.tsv"

  # Break caught: each partial publication must retain a manifest that can finish the complete projection set.
  run_projection_boundary_interrupted_workflow "$projection_boundary" "$PLAN_FILE" project
  assert_status 77
  assert_output_contains 'journal accepted; projection rebuild is recoverable'
  assert_file "$WORKSPACE/workflow-v1/.projection-transaction/manifest.tsv"
  run_workflow "$PLAN_FILE" status
  assert_status 0
  assert_not_exists "$WORKSPACE/workflow-v1/.projection-transaction"
  assert_equals "$expected_projection_hash" "$(projection_hash "$WORKSPACE" "$CHANGE/tasks.md")"
done

# Controller contract: the reducer, rather than the controller's own lifecycle
# reconstruction, decides whether work may continue or completion is defensible.
initialize_journal_fixture 'controller-interruption'
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Completion eligible: no'
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains 'READY'
assert_output_contains 'slice-1-implementer'

# Break caught: a controller must not request user authority while another
# independent lifecycle obligation remains ready.
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/result.md"
printf '%s\n' 'Dispatch: first slice implementer.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: DONE' >"$RESULT_FILE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
controller_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$controller_receipt" PASS "$RESULT_FILE"
assert_status 0
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains 'READY'
assert_output_contains 'slice-1-review'
if printf '%s\n' "$output" | grep -qF 'USER_AUTHORITY_REQUIRED'; then
  record_fail 'ready work does not request user authority'
else
  record_pass 'ready work does not request user authority'
fi
accept_review_for_cleaner

# Role findings are accepted with their role result. A mismatched count or an
# unnumbered report cannot advance the role boundary independently.
FINDINGS_DIR="$REPO/findings"
mkdir -p "$FINDINGS_DIR"
cat >"$FINDINGS_DIR/1.md" <<'EOF'
Origin role: Cleaner
Severity claim: Major
Blocking claim: no
Observed failure: Controller report contract is incomplete.
Evidence: test evidence
Violated authority: task brief
Assumptions: none
Failure scenario: report count differs
Proposed repair: validate files
Repair effects: none
EOF
printf '%s\n' 'Dispatch: Cleaner report.' >"$DISPATCH_FILE"
printf '%s\n' 'Finding count: 2' >"$RESULT_FILE"
run_workflow "$PLAN_FILE" claim slice-1-cleaner cleaner "$DISPATCH_FILE"
assert_status 0
output=$(GDD_FINDING_COUNT=2 GDD_FINDINGS_DIR="$FINDINGS_DIR" \
  "$WORKFLOW" "$PLAN_FILE" accept-active slice-1-cleaner PASS "$RESULT_FILE" 2>&1)
status=$?
assert_status 1
assert_output_contains 'finding count does not match numbered finding files'
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Active claim: slice-1-cleaner'

# A non-dependent finding parked after a Astra consultation must not turn a
# still-ready lifecycle action into a user interruption. The controller handles
# it through its digest/wake obligations after unrelated work finishes.
printf '%s\n' 'Finding count: 1' >"$RESULT_FILE"
output=$(GDD_FINDING_COUNT=1 GDD_FINDINGS_DIR="$FINDINGS_DIR" \
  "$WORKFLOW" "$PLAN_FILE" accept-active slice-1-cleaner PASS "$RESULT_FILE" 2>&1)
status=$?
assert_status 0
printf '%s\n' 'Dispatch: park the non-dependent finding after Astra advice.' >"$DISPATCH_FILE"
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-dispose controller "$DISPATCH_FILE"
assert_status 0
output=$(GDD_FINDING_ID=GDD-F0001 GDD_FINDING_STATE=PARKED \
  GDD_FINDING_RULING='Astra advised deferral; not in scope for this slice' \
  GDD_COST_IF_WRONG='The finding remains visible in the digest.' \
  GDD_WAKE_CONDITION='Astra becomes available.' \
  "$WORKFLOW" "$PLAN_FILE" accept-active finding-GDD-F0001-dispose FindingDispositionRecorded "$RESULT_FILE" 2>&1)
status=$?
assert_status 0
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains 'READY'
assert_output_contains 'slice-1-architect'

# Completion is reducer-derived. The two-slice fixture is incomplete before the
# mandatory Hardener, QA, final-suite, branch-review, and digest events, then
# becomes eligible only when every ordered static obligation is accepted.
initialize_journal_fixture 'direct-digest-bash32'
JOURNAL="$WORKSPACE/workflow-v1"
sequence=0
previous_hash=-
while IFS=$'\t' read -r obligation_id _scope _type _prerequisites _results _boundary _contract; do
  [ "$obligation_id" = obligation_id ] && continue
  case "$obligation_id" in feature-findings-digest|feature-complete) continue ;; esac
  sequence=$((sequence + 1))
  evidence_path="events/direct-digest-$sequence.md"
  write_event_evidence "$JOURNAL" "$evidence_path" "Status: PASS $obligation_id"
  evidence_digest=$(sha256_file "$JOURNAL/$evidence_path")
  append_event "$JOURNAL" "$sequence" "$sequence" "event-$sequence" "$obligation_id" ACCEPT controller "receipt-$sequence" "$evidence_path" "$evidence_digest" "$previous_hash"
  previous_hash=$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')
done <"$JOURNAL/obligations.tsv"
for digest_finding in 1 2; do
  finding_id=$(printf 'GDD-F%04d' "$digest_finding")
  sequence=$((sequence + 1))
  evidence_path="events/direct-digest-finding-$digest_finding.md"
  write_event_evidence "$JOURNAL" "$evidence_path" "Finding $digest_finding report"
  evidence_digest=$(sha256_file "$JOURNAL/$evidence_path")
  append_event "$JOURNAL" "$sequence" "$sequence" "event-$sequence" slice-1-cleaner SIDE cleaner "receipt-finding-$digest_finding" "$evidence_path" "$evidence_digest" "$previous_hash"
  previous_hash=$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')
  mkdir -p "$JOURNAL/events/event-$sequence"
  printf 'result-kind\tFindingReported\nfinding-id\t%s\nfinding-origin\tCleaner\n' "$finding_id" >"$JOURNAL/events/event-$sequence/metadata.tsv"
  sequence=$((sequence + 1))
  evidence_path="events/direct-digest-ruling-$digest_finding.md"
  write_event_evidence "$JOURNAL" "$evidence_path" "Finding $digest_finding ruling"
  evidence_digest=$(sha256_file "$JOURNAL/$evidence_path")
  append_event "$JOURNAL" "$sequence" "$sequence" "event-$sequence" "finding-$finding_id-dispose" ACCEPT controller "receipt-ruling-$digest_finding" "$evidence_path" "$evidence_digest" "$previous_hash"
  previous_hash=$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')
  mkdir -p "$JOURNAL/events/event-$sequence"
  printf 'result-kind\tFindingDispositionRecorded\nfinding-id\t%s\nfinding-state\tDISMISSED\nfinding-ruling\tRuling %s\ncost-if-wrong\tCost %s\nwake-condition\tWake %s\n' "$finding_id" "$digest_finding" "$digest_finding" "$digest_finding" >"$JOURNAL/events/event-$sequence/metadata.tsv"
done
sequence=$((sequence + 1))
evidence_path='events/direct-digest-claim.md'
write_event_evidence "$JOURNAL" "$evidence_path" 'Dispatch: write a direct portable digest.'
evidence_digest=$(sha256_file "$JOURNAL/$evidence_path")
append_event "$JOURNAL" "$sequence" "$sequence" "event-$sequence" feature-findings-digest CLAIM controller direct-digest-receipt "$evidence_path" "$evidence_digest" "$previous_hash"
DIRECT_DIGEST="$REPO/direct-digest.md"
output=$(/bin/bash "$WORKFLOW" "$PLAN_FILE" digest "$DIRECT_DIGEST" 2>&1)
status=$?
assert_status 0
assert_file_contains "$DIRECT_DIGEST" 'Finding ID: GDD-F0001'
assert_file_contains "$DIRECT_DIGEST" 'Finding ID: GDD-F0002'
direct_digest_order=$(awk '/^Finding ID:/ { print $3 }' "$DIRECT_DIGEST" | paste -sd, -)
assert_equals 'GDD-F0001,GDD-F0002' "$direct_digest_order"
assert_file_contains "$JOURNAL/events.tsv" $'feature-findings-digest\tACCEPT'

initialize_journal_fixture 'multiple-failed-accepts'
JOURNAL="$WORKSPACE/workflow-v1"
previous_hash=-
for failed_event in 1 2; do
  evidence_path="events/failed-accept-$failed_event.md"
  write_event_evidence "$JOURNAL" "$evidence_path" "Status: NOT VERIFIED $failed_event"
  evidence_digest=$(sha256_file "$JOURNAL/$evidence_path")
  obligation_id=slice-1-hardener
  [ "$failed_event" -eq 1 ] || obligation_id=slice-1-qa
  append_event "$JOURNAL" "$failed_event" "$failed_event" "event-$failed_event" "$obligation_id" ACCEPT controller "failed-receipt-$failed_event" "$evidence_path" "$evidence_digest" "$previous_hash"
  previous_hash=$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')
  mkdir -p "$JOURNAL/events/event-$failed_event"
  printf 'result-kind\tFAIL\n' >"$JOURNAL/events/event-$failed_event/metadata.tsv"
done
evidence_path='events/active-replay.md'
write_event_evidence "$JOURNAL" "$evidence_path" 'Dispatch: resume the recorded replay entry.'
evidence_digest=$(sha256_file "$JOURNAL/$evidence_path")
append_event "$JOURNAL" 3 3 event-3 finding-GDD-F0005-dispose CLAIM controller multi-fail-active-receipt "$evidence_path" "$evidence_digest" "$previous_hash"

# Break caught: two failed accepted lifecycle results must not inject a raw
# newline into macOS awk, erase static state, or lose the active receipt.
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Active claim: finding-GDD-F0005-dispose'
assert_file_contains "$JOURNAL/projections/status.tsv" $'slice-1-implementer\tREADY'
assert_file_contains "$CHANGE/tasks.md" '**Slice state:** [ ] QUEUED'
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains 'Resume claim: finding-GDD-F0005-dispose'
assert_output_contains 'Receipt: multi-fail-active-receipt'
run_workflow "$PLAN_FILE" project
assert_status 0
assert_file_contains "$CHANGE/tasks.md" '**Slice state:** [ ] QUEUED'

initialize_journal_fixture 'controller-completion'
JOURNAL="$WORKSPACE/workflow-v1"
sequence=0
previous_hash=-
while IFS=$'\t' read -r obligation_id _scope _type _prerequisites _results _boundary _contract; do
  [ "$obligation_id" = obligation_id ] && continue
  [ "$obligation_id" = feature-complete ] && continue
  sequence=$((sequence + 1))
  evidence_path="events/controller-$sequence.md"
  write_event_evidence "$JOURNAL" "$evidence_path" "Status: PASS $obligation_id"
  evidence_digest=$(sha256_file "$JOURNAL/$evidence_path")
  append_event "$JOURNAL" "$sequence" "$sequence" "event-$sequence" "$obligation_id" ACCEPT controller "receipt-$sequence" "$evidence_path" "$evidence_digest" "$previous_hash"
  previous_hash=$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')
done <"$JOURNAL/obligations.tsv"
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Completion eligible: yes'
printf '%s\n' 'Dispatch: write completion evidence.' >"$DISPATCH_FILE"
run_workflow "$PLAN_FILE" claim feature-complete controller "$DISPATCH_FILE"
assert_status 0
run_workflow "$PLAN_FILE" complete "$REPO/completion.md"
assert_status 0
assert_output_contains 'Completion evidence:'
assert_file_contains "$REPO/completion.md" 'Workflow status: COMPLETE'
assert_file_contains "$REPO/completion.md" 'Branch review evidence: events/controller-17.md'
assert_file_contains "$REPO/completion.md" 'Findings digest: events/controller-19.md'
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains COMPLETE

# Every mandatory completion event is indispensable and ordered. Test deletion
# and reordering in isolated copies of the completed journal.
COMPLETED_JOURNAL="$TEST_ROOT/controller-completion-baseline"
cp -R "$JOURNAL" "$COMPLETED_JOURNAL"
first_completion_event=$(awk -F '\t' 'NR == 2 { print $3 }' "$COMPLETED_JOURNAL/events.tsv")
last_completion_event=$(tail -n 1 "$COMPLETED_JOURNAL/events.tsv" | awk -F '\t' '{ print $3 }')
while IFS=$'\t' read -r event_id; do
  rm -rf "$JOURNAL"
  cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
  awk -F '\t' -v id="$event_id" 'NR == 1 || $3 != id' "$JOURNAL/events.tsv" >"$JOURNAL/events.tmp"
  mv "$JOURNAL/events.tmp" "$JOURNAL/events.tsv"
  run_workflow "$PLAN_FILE" status
  if [ "$event_id" = "$last_completion_event" ]; then
    assert_status 0
    run_workflow "$PLAN_FILE" next
    assert_status 0
    if printf '%s\n' "$output" | grep -qF COMPLETE; then
      record_fail 'deleting the completion event prevents COMPLETE'
    else
      record_pass 'deleting the completion event prevents COMPLETE'
    fi
  else
    assert_status 1
    assert_output_contains INVALID
  fi

  rm -rf "$JOURNAL"
  cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
  {
    head -n 1 "$JOURNAL/events.tsv"
    if [ "$event_id" = "$first_completion_event" ]; then
      awk -F '\t' -v id="$event_id" 'NR > 1 && $3 != id' "$JOURNAL/events.tsv"
      awk -F '\t' -v id="$event_id" 'NR > 1 && $3 == id' "$JOURNAL/events.tsv"
    else
      awk -F '\t' -v id="$event_id" 'NR > 1 && $3 == id' "$JOURNAL/events.tsv"
      awk -F '\t' -v id="$event_id" 'NR > 1 && $3 != id' "$JOURNAL/events.tsv"
    fi
  } >"$JOURNAL/events.tmp"
  mv "$JOURNAL/events.tmp" "$JOURNAL/events.tsv"
  run_workflow "$PLAN_FILE" status
  assert_status 1
  assert_output_contains INVALID
done < <(awk -F '\t' 'NR > 1 { print $3 }' "$COMPLETED_JOURNAL/events.tsv")

# Each mutation changes one completed-journal fact. The reducer must fail
# closed instead of accepting a narrated completion after journal tampering.
rm -rf "$JOURNAL"
cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains COMPLETE

rm -rf "$JOURNAL"
cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
awk 'NR == 1 || NR != 2' "$JOURNAL/events.tsv" >"$JOURNAL/events.tmp"
mv "$JOURNAL/events.tmp" "$JOURNAL/events.tsv"
assert_completion_mutation_rejected 'deleting an event row'

rm -rf "$JOURNAL"
cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
awk 'NR == 2 { print } { print }' "$JOURNAL/events.tsv" >"$JOURNAL/events.tmp"
mv "$JOURNAL/events.tmp" "$JOURNAL/events.tsv"
assert_completion_mutation_rejected 'duplicating an event row'

rm -rf "$JOURNAL"
cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
{
  head -n 1 "$JOURNAL/events.tsv"
  sed -n '3p' "$JOURNAL/events.tsv"
  sed -n '2p' "$JOURNAL/events.tsv"
  sed -n '4,$p' "$JOURNAL/events.tsv"
} >"$JOURNAL/events.tmp"
mv "$JOURNAL/events.tmp" "$JOURNAL/events.tsv"
assert_completion_mutation_rejected 'swapping two event rows'

rm -rf "$JOURNAL"
cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
awk -F '\t' 'BEGIN { OFS = FS } NR == 2 { $4 = "slice-999-implementer" } { print }' "$JOURNAL/events.tsv" >"$JOURNAL/events.tmp"
mv "$JOURNAL/events.tmp" "$JOURNAL/events.tsv"
assert_completion_mutation_rejected 'changing an obligation ID'

rm -rf "$JOURNAL"
cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
awk -F '\t' 'BEGIN { OFS = FS } NR == 2 { $7 = "tampered-receipt" } { print }' "$JOURNAL/events.tsv" >"$JOURNAL/events.tmp"
mv "$JOURNAL/events.tmp" "$JOURNAL/events.tsv"
assert_completion_mutation_rejected 'changing a receipt'

rm -rf "$JOURNAL"
cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
awk -F '\t' 'BEGIN { OFS = FS } NR == 2 { $9 = "0000000000000000000000000000000000000000000000000000000000000000" } { print }' "$JOURNAL/events.tsv" >"$JOURNAL/events.tmp"
mv "$JOURNAL/events.tmp" "$JOURNAL/events.tsv"
assert_completion_mutation_rejected 'changing an evidence digest'

for mandatory_obligation in slice-1-hardener slice-1-qa slice-1-final-suite; do
  rm -rf "$JOURNAL"
  cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
  mandatory_evidence_path="$(awk -F '\t' -v obligation="$mandatory_obligation" '$4 == obligation { print $8; exit }' "$JOURNAL/events.tsv")"
  rm -f "$JOURNAL/$mandatory_evidence_path"
  assert_completion_mutation_rejected "removing $mandatory_obligation evidence"
done

rm -rf "$JOURNAL"
cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
branch_review_evidence_path="$(awk -F '\t' '$4 == "feature-branch-review" { print $8; exit }' "$JOURNAL/events.tsv")"
printf '%s\n' 'replacement branch-review evidence' >"$JOURNAL/$branch_review_evidence_path"
assert_completion_mutation_rejected 'replacing Branch Review evidence'

rm -rf "$JOURNAL"
cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
awk -F '\t' 'NR == 1 || $4 != "feature-findings-digest"' "$JOURNAL/events.tsv" >"$JOURNAL/events.tmp"
mv "$JOURNAL/events.tmp" "$JOURNAL/events.tsv"
assert_completion_mutation_rejected 'removing the findings digest event'

rm -rf "$JOURNAL"
cp -R "$COMPLETED_JOURNAL" "$JOURNAL"
unknown_sequence="$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $1 + 1 }')"
unknown_revision="$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $2 + 1 }')"
unknown_previous_hash="$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')"
write_event_evidence "$JOURNAL" 'events/unknown-kind.md' 'unknown event kind'
unknown_evidence_digest="$(sha256_file "$JOURNAL/events/unknown-kind.md")"
append_event "$JOURNAL" "$unknown_sequence" "$unknown_revision" unknown-kind-event feature-complete UNKNOWN controller unknown-receipt events/unknown-kind.md "$unknown_evidence_digest" "$unknown_previous_hash"
assert_completion_mutation_rejected 'appending an unknown event kind'

# Break caught: deleting a mandatory lifecycle event invalidates its hash chain
# and leaves completion ineligible instead of accepting a partial ceremony.
initialize_journal_fixture 'controller-completion-missing-hardener'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/missing-hardener.md' 'mandatory event was removed'
missing_digest=$(sha256_file "$JOURNAL/events/missing-hardener.md")
append_event "$JOURNAL" 2 2 event-2 slice-1-hardener ACCEPT controller receipt-2 events/missing-hardener.md "$missing_digest" -
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains INVALID

# Lifecycle roles cannot advance without an explicit zero or a numbered,
# complete finding set bound to the role report.
initialize_journal_fixture 'mandatory-grouped-role-result'
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/result.md"
printf '%s\n' 'Dispatch: implement before Cleaner.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: DONE' >"$RESULT_FILE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
grouped_implementer_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$grouped_implementer_receipt" PASS "$RESULT_FILE"
assert_status 0
accept_review_for_cleaner
run_workflow "$PLAN_FILE" claim slice-1-cleaner cleaner "$DISPATCH_FILE"
assert_status 0
grouped_cleaner_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$grouped_cleaner_receipt" PASS "$RESULT_FILE"
assert_status 1
assert_output_contains 'lifecycle role result requires grouped finding acceptance via accept-active'
run_workflow "$PLAN_FILE" accept-active slice-1-cleaner PASS "$RESULT_FILE"
assert_status 1
assert_output_contains 'lifecycle role result requires grouped finding evidence'
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Active claim: slice-1-cleaner'

# Break caught: two files that normalize to the same finding number cannot
# create duplicate FindingReported events in the accepted role transaction.
FINDINGS_DIR="$REPO/duplicate-findings"
mkdir -p "$FINDINGS_DIR"
for finding_file in 1.md 01.md; do
  cat >"$FINDINGS_DIR/$finding_file" <<'EOF'
Origin role: Cleaner
Severity claim: Major
Blocking claim: no
Observed failure: duplicate number
Evidence: test evidence
Violated authority: task brief
Assumptions: none
Failure scenario: duplicate number
Proposed repair: reject duplicate
Repair effects: none
EOF
done
printf '%s\n' 'Finding count: 2' >"$RESULT_FILE"
output=$(GDD_FINDINGS_DIR="$FINDINGS_DIR" \
  "$WORKFLOW" "$PLAN_FILE" accept-active slice-1-cleaner PASS "$RESULT_FILE" 2>&1)
status=$?
assert_status 1
assert_output_contains 'duplicate finding number'

# Break caught: a file that is not one numbered Markdown finding cannot be
# silently excluded from the grouped acceptance transaction.
rm -f "$FINDINGS_DIR/1.md" "$FINDINGS_DIR/01.md"
printf '%s\n' 'not a finding report' >"$FINDINGS_DIR/unexpected.txt"
printf '%s\n' 'Finding count: 1' >"$RESULT_FILE"
output=$(GDD_FINDINGS_DIR="$FINDINGS_DIR" \
  "$WORKFLOW" "$PLAN_FILE" accept-active slice-1-cleaner PASS "$RESULT_FILE" 2>&1)
status=$?
assert_status 1
assert_output_contains 'unexpected finding file'

# Break caught: a finding file cannot claim a different lifecycle origin than
# the role whose result is being accepted.
rm -f "$FINDINGS_DIR/unexpected.txt"
cat >"$FINDINGS_DIR/1.md" <<'EOF'
Origin role: Architect
Severity claim: Major
Blocking claim: no
Observed failure: origin is not Cleaner.
Evidence: test evidence
Violated authority: task brief
Assumptions: none
Failure scenario: wrong role owns the finding
Proposed repair: reject origin mismatch
Repair effects: none
EOF
output=$(GDD_FINDINGS_DIR="$FINDINGS_DIR" \
  "$WORKFLOW" "$PLAN_FILE" accept-active slice-1-cleaner PASS "$RESULT_FILE" 2>&1)
status=$?
assert_status 1
assert_output_contains 'finding origin differs from claimed role: Cleaner'

# The role report declares one, and only one, authoritative finding count.
printf '%s\n' 'Finding count: 1' >>"$RESULT_FILE"
output=$(GDD_FINDINGS_DIR="$FINDINGS_DIR" \
  "$WORKFLOW" "$PLAN_FILE" accept-active slice-1-cleaner PASS "$RESULT_FILE" 2>&1)
status=$?
assert_status 1
assert_output_contains 'role report must contain exactly one Finding count: N'

# A dependent BLOCKED finding prevents its stated boundary. With no other legal
# action left, next must derive USER_AUTHORITY_REQUIRED.
initialize_journal_fixture 'blocked-dependent-boundary'
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/result.md"
printf '%s\n' 'Dispatch: implement before blocking finding.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: DONE' >"$RESULT_FILE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
blocked_implementer_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$blocked_implementer_receipt" PASS "$RESULT_FILE"
assert_status 0
accept_review_for_cleaner
run_workflow "$PLAN_FILE" claim slice-1-cleaner cleaner "$DISPATCH_FILE"
assert_status 0
FINDINGS_DIR="$REPO/blocked-findings"
mkdir -p "$FINDINGS_DIR"
cat >"$FINDINGS_DIR/1.md" <<'EOF'
Origin role: Cleaner
Severity claim: Critical
Blocking claim: yes
Observed failure: the Architect boundary is unsafe.
Evidence: test evidence
Violated authority: task brief
Assumptions: none
Failure scenario: dependent review starts
Proposed repair: request authority
Repair effects: none
EOF
printf '%s\n' 'Finding count: 1' >"$RESULT_FILE"
output=$(GDD_FINDINGS_DIR="$FINDINGS_DIR" \
  "$WORKFLOW" "$PLAN_FILE" accept-active slice-1-cleaner PASS "$RESULT_FILE" 2>&1)
status=$?
assert_status 0
printf '%s\n' 'Dispatch: block the Architect boundary.' >"$DISPATCH_FILE"
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-dispose controller "$DISPATCH_FILE"
assert_status 0
output=$(GDD_FINDING_ID=GDD-F0001 GDD_FINDING_STATE=BLOCKED \
  GDD_BLOCKING_BOUNDARY=slice-1-architect \
  "$WORKFLOW" "$PLAN_FILE" accept-active finding-GDD-F0001-dispose FindingDispositionRecorded "$RESULT_FILE" 2>&1)
status=$?
assert_status 0
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains USER_AUTHORITY_REQUIRED

# Binding verification evidence is validated by the workflow admission boundary,
# so direct adapters cannot advance a Hardener, QA, or final-suite gate with an
# arbitrary role report. Every rejection leaves the journal and evidence tree
# exactly as it was before the attempted acceptance.
setup_claimed_hardener 'hardener-status-fail'
HARDENER_RESULT="$REPO/hardener-fail.md"
write_role_result "$HARDENER_RESULT" FAIL
before_snapshot=$(journal_and_evidence_sha "$JOURNAL")
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-hardener PASS "$HARDENER_RESULT"
assert_admission_rejected_unchanged 'Hardener Status: FAIL' "Hardener evidence must contain 'Status: VERIFIED'" "$before_snapshot"

setup_claimed_hardener 'hardener-status-missing'
HARDENER_RESULT="$REPO/hardener-missing-status.md"
printf '%s\n' 'Finding count: 0' >"$HARDENER_RESULT"
before_snapshot=$(journal_and_evidence_sha "$JOURNAL")
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-hardener PASS "$HARDENER_RESULT"
assert_admission_rejected_unchanged 'Hardener missing Status: VERIFIED' "Hardener evidence must contain 'Status: VERIFIED'" "$before_snapshot"

setup_claimed_hardener 'hardener-empty-evidence'
HARDENER_RESULT="$REPO/hardener-empty.md"
: >"$HARDENER_RESULT"
before_snapshot=$(journal_and_evidence_sha "$JOURNAL")
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-hardener PASS "$HARDENER_RESULT"
assert_admission_rejected_unchanged 'Hardener empty evidence' 'Hardener evidence is missing or empty' "$before_snapshot"

setup_claimed_qa 'qa-status-fail'
QA_RESULT="$REPO/qa-fail.md"
FINAL_SUITE_RESULT="$REPO/final-suite.md"
write_role_result "$QA_RESULT" FAIL
printf '%s\n' 'Status: PASS' >"$FINAL_SUITE_RESULT"
before_snapshot=$(journal_and_evidence_sha "$JOURNAL")
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-qa SliceVerifiedMacro "$QA_RESULT" "$FINAL_SUITE_RESULT"
assert_admission_rejected_unchanged 'QA Status: FAIL' "QA evidence must contain 'Status: VERIFIED'" "$before_snapshot"

setup_claimed_qa 'qa-status-missing'
QA_RESULT="$REPO/qa-missing-status.md"
FINAL_SUITE_RESULT="$REPO/final-suite.md"
printf '%s\n' 'Finding count: 0' >"$QA_RESULT"
printf '%s\n' 'Status: PASS' >"$FINAL_SUITE_RESULT"
before_snapshot=$(journal_and_evidence_sha "$JOURNAL")
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-qa SliceVerifiedMacro "$QA_RESULT" "$FINAL_SUITE_RESULT"
assert_admission_rejected_unchanged 'QA missing Status: VERIFIED' "QA evidence must contain 'Status: VERIFIED'" "$before_snapshot"

setup_claimed_qa 'qa-empty-evidence'
QA_RESULT="$REPO/qa-empty.md"
FINAL_SUITE_RESULT="$REPO/final-suite.md"
: >"$QA_RESULT"
printf '%s\n' 'Status: PASS' >"$FINAL_SUITE_RESULT"
before_snapshot=$(journal_and_evidence_sha "$JOURNAL")
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-qa SliceVerifiedMacro "$QA_RESULT" "$FINAL_SUITE_RESULT"
assert_admission_rejected_unchanged 'QA empty evidence' 'QA evidence is missing or empty' "$before_snapshot"

setup_claimed_qa 'final-suite-status-fail'
QA_RESULT="$REPO/qa-verified.md"
FINAL_SUITE_RESULT="$REPO/final-suite-fail.md"
write_role_result "$QA_RESULT" VERIFIED
printf '%s\n' 'Status: FAIL' >"$FINAL_SUITE_RESULT"
before_snapshot=$(journal_and_evidence_sha "$JOURNAL")
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-qa SliceVerifiedMacro "$QA_RESULT" "$FINAL_SUITE_RESULT"
assert_admission_rejected_unchanged 'Final suite Status: FAIL' "Final slice suite evidence must contain 'Status: PASS'" "$before_snapshot"

setup_claimed_qa 'final-suite-status-missing'
QA_RESULT="$REPO/qa-verified.md"
FINAL_SUITE_RESULT="$REPO/final-suite-missing-status.md"
write_role_result "$QA_RESULT" VERIFIED
printf '%s\n' 'Suite completed.' >"$FINAL_SUITE_RESULT"
before_snapshot=$(journal_and_evidence_sha "$JOURNAL")
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-qa SliceVerifiedMacro "$QA_RESULT" "$FINAL_SUITE_RESULT"
assert_admission_rejected_unchanged 'Final suite missing Status: PASS' "Final slice suite evidence must contain 'Status: PASS'" "$before_snapshot"

setup_claimed_qa 'final-suite-empty-evidence'
QA_RESULT="$REPO/qa-verified.md"
FINAL_SUITE_RESULT="$REPO/final-suite-empty.md"
write_role_result "$QA_RESULT" VERIFIED
: >"$FINAL_SUITE_RESULT"
before_snapshot=$(journal_and_evidence_sha "$JOURNAL")
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-qa SliceVerifiedMacro "$QA_RESULT" "$FINAL_SUITE_RESULT"
assert_admission_rejected_unchanged 'Final suite empty evidence' 'Final slice suite evidence is missing or empty' "$before_snapshot"

# Hardener REVERIFY_REQUIRED is a FAIL the engine accepts (spec D4).
setup_claimed_hardener 'hardener-reverify-required'
hardener_result="$REPO/hardener-reverify.md"
write_role_result "$hardener_result" REVERIFY_REQUIRED
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-hardener FAIL "$hardener_result"
assert_status 0
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Ready obligation: slice-1-hardener'

# A review obligation authorizes Task Reviewer and Re-reviewer findings and
# records each file's own origin. Any other origin is rejected.
initialize_journal_fixture 'review-origins'
JOURNAL="$WORKSPACE/workflow-v1"
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: review the slice.' >"$DISPATCH_FILE"
IMPLEMENTER_RESULT="$REPO/implementer.md"
printf 'Status: DONE\n' >"$IMPLEMENTER_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
implementer_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$implementer_receipt" PASS "$IMPLEMENTER_RESULT"
assert_status 0
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Ready obligation: slice-1-review'
assert_file_contains "$CHANGE/tasks.md" '**Slice state:** [~] REVIEWING'
REVIEW_FINDINGS="$REPO/review-findings"
mkdir -p "$REVIEW_FINDINGS"
REVIEW_RESULT="$REPO/review-result.md"
printf 'Status: FAIL\nFinding count: 1\n' >"$REVIEW_RESULT"
cat >"$REVIEW_FINDINGS/1.md" <<'EOF'
Origin role: Cleaner
Severity claim: Important
Blocking claim: yes
Observed failure: a worker origin on a review obligation.
Evidence: test evidence
Violated authority: task brief
Assumptions: none
Failure scenario: the wrong role owns the finding
Proposed repair: reject the origin
Repair effects: none
EOF
run_workflow "$PLAN_FILE" claim slice-1-review task-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$REVIEW_FINDINGS" "$PLAN_FILE" accept-active slice-1-review FAIL "$REVIEW_RESULT"
assert_status 1
assert_output_contains 'finding origin differs from claimed role: Task Reviewer or Re-reviewer'
sed -i.bak 's/^Origin role: Cleaner$/Origin role: Re-reviewer/' "$REVIEW_FINDINGS/1.md"
rm -f "$REVIEW_FINDINGS/1.md.bak"
run_grouped_workflow "$REVIEW_FINDINGS" "$PLAN_FILE" accept-active slice-1-review FAIL "$REVIEW_RESULT"
assert_status 0
review_metadata=$(grep -l $'^finding-origin\tRe-reviewer$' "$JOURNAL"/events/*/metadata.tsv | head -n 1)
if [ -n "$review_metadata" ]; then
  record_pass 'review finding metadata records the file origin Re-reviewer'
else
  record_fail 'review finding metadata records the file origin Re-reviewer'
fi
run_workflow "$PLAN_FILE" status
assert_status 0
assert_file_contains "$CHANGE/tasks.md" '**Slice state:** [~] REVIEWING'

# Break caught: a BLOCKED implementer report must not advance the review gate.
initialize_journal_fixture 'implementer-blocked-status'
DISPATCH_FILE="$REPO/dispatch.md"
IMPLEMENTER_BLOCKED_RESULT="$REPO/implementer-blocked.md"
printf '%s\n' 'Dispatch: implement the slice.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: BLOCKED' >"$IMPLEMENTER_BLOCKED_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
run_workflow "$PLAN_FILE" accept-active slice-1-implementer PASS "$IMPLEMENTER_BLOCKED_RESULT"
assert_status 1
assert_output_contains 'Implementer evidence must contain one of Status: DONE | DONE_WITH_CONCERNS'
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Active claim: slice-1-implementer'

write_review_finding() {
  local output=$1 origin=$2 summary=$3 severity=${4:-Important}
  cat >"$output" <<EOF
Origin role: $origin
Severity claim: $severity
Blocking claim: yes
Observed failure: $summary
Evidence: test evidence
Violated authority: task brief
Assumptions: none
Failure scenario: the defect ships
Proposed repair: fix it
Repair effects: the fixer changes one file
EOF
}

finding_accept() {
  local obligation=$1 result_kind=$2 evidence=$3
  shift 3
  output=$(env "$@" "$WORKFLOW" "$PLAN_FILE" accept-active "$obligation" "$result_kind" "$evidence" 2>&1)
  status=$?
}

ready_obligation() {
  "$WORKFLOW" "$PLAN_FILE" next 2>/dev/null | sed -n 's/^Ready obligation: //p' | head -n 1
}

assert_next() {
  local expected=$1 actual
  actual=$(ready_obligation)
  if [ "$actual" = "$expected" ]; then
    record_pass "next obligation is $expected"
  else
    record_fail "next obligation is $expected (got: $actual)"
  fi
}

# Spec D3: Task Reviewer FAIL, consult, dispose, one fixer dispatch per round,
# re-review before any finish, finish, resolve, second round, closing PASS.
initialize_journal_fixture 'review-fix-round'
JOURNAL="$WORKSPACE/workflow-v1"
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: walk one fix round.' >"$DISPATCH_FILE"
EVIDENCE="$REPO/evidence.md"
printf 'Status: DONE\n' >"$EVIDENCE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
round_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$round_receipt" PASS "$EVIDENCE"
assert_status 0
ROUND_FINDINGS="$REPO/round-findings"
mkdir -p "$ROUND_FINDINGS"
write_review_finding "$ROUND_FINDINGS/1.md" 'Task Reviewer' 'the first defect'
write_review_finding "$ROUND_FINDINGS/2.md" 'Task Reviewer' 'the second defect'
REVIEW_RESULT="$REPO/review-result.md"
printf 'Status: FAIL\nFinding count: 2\n' >"$REVIEW_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-review task-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$ROUND_FINDINGS" "$PLAN_FILE" accept-active slice-1-review FAIL "$REVIEW_RESULT"
assert_status 0
run_workflow "$PLAN_FILE" status
assert_status 0
assert_file_contains "$JOURNAL/projections/status.tsv" $'slice-1-review\tPENDING'
assert_file_contains "$JOURNAL/projections/status.tsv" $'finding-GDD-F0001-consult-1\tPENDING'
assert_next finding-GDD-F0001-dispose

# A consultation is claimable while PENDING, like a wake check.
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-consult-1 controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-consult-1 FindingConsultRecorded "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=CONSULT GDD_FINDING_EVENT_NAME=consult-1
assert_status 0
run_workflow "$PLAN_FILE" status
assert_status 0
assert_file_contains "$JOURNAL/projections/status.tsv" $'finding-GDD-F0001-consult-1\tCOMPLETE'
assert_file_contains "$JOURNAL/projections/status.tsv" $'finding-GDD-F0001-consult-2\tPENDING'

for finding in GDD-F0001 GDD-F0002; do
  run_workflow "$PLAN_FILE" claim "finding-$finding-dispose" controller "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-dispose" FindingDispositionRecorded "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
    GDD_FINDING_STATE=REPAIRING GDD_FINDING_EVENT_NAME=transition-repairing GDD_REPLAY_THROUGH=re-review
  assert_status 0
done
assert_next finding-GDD-F0001-repair-start-1
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-start-1 fixer-max "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-repair-start-1 RepairStarted "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=REPAIR_START GDD_FINDING_EVENT_NAME=repair-start GDD_REPAIR_ROUND=1
assert_status 0
assert_next finding-GDD-F0002-repair-start-1
run_workflow "$PLAN_FILE" status
assert_file_contains "$JOURNAL/projections/status.tsv" $'finding-GDD-F0001-repair-result\tPENDING'
run_workflow "$PLAN_FILE" claim finding-GDD-F0002-repair-start-1 fixer-max "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0002-repair-start-1 RepairStarted "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0002 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=REPAIR_START GDD_FINDING_EVENT_NAME=repair-start GDD_REPAIR_ROUND=1
assert_status 0
assert_next finding-GDD-F0001-repair-result
for finding in GDD-F0001 GDD-F0002; do
  run_workflow "$PLAN_FILE" claim "finding-$finding-repair-result" fixer-max "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-repair-result" RepairAccepted "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
    GDD_FINDING_STATE=REPAIR_RESULT GDD_FINDING_EVENT_NAME=repair-result GDD_REPAIR_ROUND=1 GDD_REPLAY_THROUGH=re-review
  assert_status 0
done
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-finish-1 controller "$DISPATCH_FILE"
assert_status 1
assert_output_contains 'not the selected ready action'
assert_next slice-1-review
RE_REVIEW_FINDINGS="$REPO/re-review-findings"
mkdir -p "$RE_REVIEW_FINDINGS"
write_review_finding "$RE_REVIEW_FINDINGS/1.md" Re-reviewer 'new breakage from the fix'
printf 'Status: FAIL\nFinding count: 1\n' >"$REVIEW_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-review re-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$RE_REVIEW_FINDINGS" "$PLAN_FILE" accept-active slice-1-review FAIL "$REVIEW_RESULT"
assert_status 0
assert_next finding-GDD-F0001-repair-finish-1
assert_file_contains "$JOURNAL/projections/status.tsv" $'finding-GDD-F0003-dispose\tPENDING'
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-finish-1 controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-repair-finish-1 RepairFinished "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=REPAIR_FINISH GDD_FINDING_EVENT_NAME=repair-finish GDD_REPAIR_ROUND=1 GDD_REPLAY_STATUS=VERIFIED
assert_status 0
run_workflow "$PLAN_FILE" claim finding-GDD-F0002-repair-finish-1 controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0002-repair-finish-1 RepairFinished "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0002 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=REPAIR_FINISH GDD_FINDING_EVENT_NAME=repair-finish GDD_REPAIR_ROUND=1 GDD_REPLAY_STATUS=FAILED
assert_status 0
assert_file_contains "$JOURNAL/projections/status.tsv" $'finding-GDD-F0003-dispose\tREADY'
assert_next finding-GDD-F0003-dispose
run_workflow "$PLAN_FILE" claim finding-GDD-F0003-dispose controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0003-dispose FindingDispositionRecorded "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0003 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN=Re-reviewer \
  GDD_FINDING_STATE=REPAIRING GDD_FINDING_EVENT_NAME=transition-repairing GDD_REPLAY_THROUGH=re-review
assert_status 0
assert_next finding-GDD-F0001-resolve
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-resolve controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-resolve FindingResolved "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=RESOLVED GDD_FINDING_EVENT_NAME=transition-resolved
assert_status 0
assert_next finding-GDD-F0002-repair-start-2
for finding in GDD-F0002 GDD-F0003; do
  origin='Task Reviewer'
  [ "$finding" = GDD-F0002 ] || origin=Re-reviewer
  run_workflow "$PLAN_FILE" claim "finding-$finding-repair-start-2" fixer-max "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-repair-start-2" RepairStarted "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN="$origin" \
    GDD_FINDING_STATE=REPAIR_START GDD_FINDING_EVENT_NAME=repair-start GDD_REPAIR_ROUND=2
  assert_status 0
done
for finding in GDD-F0002 GDD-F0003; do
  origin='Task Reviewer'
  [ "$finding" = GDD-F0002 ] || origin=Re-reviewer
  run_workflow "$PLAN_FILE" claim "finding-$finding-repair-result" fixer-max "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-repair-result" RepairAccepted "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN="$origin" \
    GDD_FINDING_STATE=REPAIR_RESULT GDD_FINDING_EVENT_NAME=repair-result GDD_REPAIR_ROUND=2 GDD_REPLAY_THROUGH=re-review
  assert_status 0
done
assert_next slice-1-review
printf 'Status: FAIL\nFinding count: 0\n' >"$REVIEW_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-review re-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-review FAIL "$REVIEW_RESULT"
assert_status 0
for finding in GDD-F0002 GDD-F0003; do
  origin='Task Reviewer'
  [ "$finding" = GDD-F0002 ] || origin=Re-reviewer
  run_workflow "$PLAN_FILE" claim "finding-$finding-repair-finish-2" controller "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-repair-finish-2" RepairFinished "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN="$origin" \
    GDD_FINDING_STATE=REPAIR_FINISH GDD_FINDING_EVENT_NAME=repair-finish GDD_REPAIR_ROUND=2 GDD_REPLAY_STATUS=VERIFIED
  assert_status 0
done
# Both accepted repairs must close before either finding can resolve.
for finding in GDD-F0002 GDD-F0003; do
  origin='Task Reviewer'
  [ "$finding" = GDD-F0002 ] || origin=Re-reviewer
  run_workflow "$PLAN_FILE" claim "finding-$finding-resolve" controller "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-resolve" FindingResolved "$EVIDENCE" \
    GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN="$origin" \
    GDD_FINDING_STATE=RESOLVED GDD_FINDING_EVENT_NAME=transition-resolved
  assert_status 0
done
review_invalidations=$(awk -F '\t' '$5 == "EvidenceInvalidated" && $4 == "slice-1-review" { count++ } END { print count + 0 }' "$JOURNAL/events.tsv")
assert_equals 4 "$review_invalidations"
assert_next slice-1-review
printf 'Status: PASS\nFinding count: 0\n' >"$REVIEW_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-review re-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-review PASS "$REVIEW_RESULT"
assert_status 0
assert_next slice-1-cleaner
assert_file_contains "$CHANGE/tasks.md" '**Slice state:** [~] VERIFYING: CLEANER'

# Spec D8: feature closing with one combined round and both re-reviews.
initialize_journal_fixture 'feature-closing-round'
JOURNAL="$WORKSPACE/workflow-v1"
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: close the feature.' >"$DISPATCH_FILE"
EVIDENCE="$REPO/evidence.md"
printf 'Status: PASS\n' >"$EVIDENCE"
sequence=0
previous_hash=-
while IFS=$'\t' read -r obligation_id _scope _type _prerequisites _results _boundary _contract; do
  [ "$obligation_id" = obligation_id ] && continue
  case "$obligation_id" in feature-*) continue ;; esac
  sequence=$((sequence + 1))
  evidence_path="events/closing-$sequence.md"
  write_event_evidence "$JOURNAL" "$evidence_path" "Status: PASS $obligation_id"
  evidence_digest=$(sha256_file "$JOURNAL/$evidence_path")
  append_event "$JOURNAL" "$sequence" "$sequence" "event-$sequence" "$obligation_id" ACCEPT controller "receipt-$sequence" "$evidence_path" "$evidence_digest" "$previous_hash"
  previous_hash=$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')
done <"$JOURNAL/obligations.tsv"
assert_next feature-branch-review
BRANCH_FINDINGS="$REPO/branch-findings"
mkdir -p "$BRANCH_FINDINGS"
write_review_finding "$BRANCH_FINDINGS/1.md" 'Branch Reviewer' 'a seam between slices' Minor
BRANCH_RESULT="$REPO/branch-result.md"
printf 'Status: FAIL\nFinding count: 1\n' >"$BRANCH_RESULT"
run_workflow "$PLAN_FILE" claim feature-branch-review branch-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$BRANCH_FINDINGS" "$PLAN_FILE" accept-active feature-branch-review FAIL "$BRANCH_RESULT"
assert_status 0
assert_next finding-GDD-F0001-dispose
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-dispose controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-dispose FindingDispositionRecorded "$EVIDENCE" GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Branch Reviewer' GDD_FINDING_STATE=REPAIRING GDD_FINDING_EVENT_NAME=transition-repairing GDD_REPLAY_THROUGH=re-review
assert_status 0
assert_next feature-security-review
SECURITY_FINDINGS="$REPO/security-findings"
mkdir -p "$SECURITY_FINDINGS"
write_review_finding "$SECURITY_FINDINGS/1.md" 'Security Reviewer' 'a cross-slice authorization gap' Critical
SECURITY_RESULT="$REPO/security-result.md"
printf 'Status: FAIL\nFinding count: 1\n' >"$SECURITY_RESULT"
run_workflow "$PLAN_FILE" claim feature-security-review security-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$SECURITY_FINDINGS" "$PLAN_FILE" accept-active feature-security-review FAIL "$SECURITY_RESULT"
assert_status 0
security_metadata=$(grep -l $'^finding-origin\tSecurity Reviewer$' "$JOURNAL"/events/*/metadata.tsv | head -n 1)
if [ -n "$security_metadata" ]; then
  record_pass 'feature security review records a Security Reviewer finding'
else
  record_fail 'feature security review records a Security Reviewer finding'
fi
assert_next finding-GDD-F0002-dispose
run_workflow "$PLAN_FILE" claim finding-GDD-F0002-dispose controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0002-dispose FindingDispositionRecorded "$EVIDENCE" GDD_FINDING_ID=GDD-F0002 GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Security Reviewer' GDD_FINDING_STATE=REPAIRING GDD_FINDING_EVENT_NAME=transition-repairing GDD_REPLAY_THROUGH=re-review
assert_status 0
for finding in GDD-F0001 GDD-F0002; do
  origin='Branch Reviewer'; [ "$finding" = GDD-F0001 ] || origin='Security Reviewer'
  run_workflow "$PLAN_FILE" claim "finding-$finding-repair-start-1" fixer-max "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-repair-start-1" RepairStarted "$EVIDENCE" GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN="$origin" GDD_FINDING_STATE=REPAIR_START GDD_FINDING_EVENT_NAME=repair-start GDD_REPAIR_ROUND=1
  assert_status 0
done
for finding in GDD-F0001 GDD-F0002; do
  origin='Branch Reviewer'; [ "$finding" = GDD-F0001 ] || origin='Security Reviewer'
  run_workflow "$PLAN_FILE" claim "finding-$finding-repair-result" fixer-max "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-$finding-repair-result" RepairAccepted "$EVIDENCE" GDD_FINDING_ID="$finding" GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN="$origin" GDD_FINDING_STATE=REPAIR_RESULT GDD_FINDING_EVENT_NAME=repair-result GDD_REPAIR_ROUND=1 GDD_REPLAY_THROUGH=re-review
  assert_status 0
done
feature_invalidations=$(awk -F '\t' '$5 == "EvidenceInvalidated" { print $4 }' "$JOURNAL/events.tsv" | sort | uniq -c | awk '{ print $2 "=" $1 }' | paste -sd, -)
assert_equals 'feature-branch-review=2,feature-security-review=2' "$feature_invalidations"
assert_next feature-branch-review
printf 'Status: FAIL\nFinding count: 0\n' >"$BRANCH_RESULT"
run_workflow "$PLAN_FILE" claim feature-branch-review branch-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active feature-branch-review FAIL "$BRANCH_RESULT"
assert_status 0
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-finish-1 controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-repair-finish-1 RepairFinished "$EVIDENCE" GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Branch Reviewer' GDD_FINDING_STATE=REPAIR_FINISH GDD_FINDING_EVENT_NAME=repair-finish GDD_REPAIR_ROUND=1 GDD_REPLAY_STATUS=FAILED
assert_status 0
assert_next finding-GDD-F0001-dispose
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-dispose controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-dispose FindingDispositionRecorded "$EVIDENCE" GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Branch Reviewer' GDD_FINDING_STATE=DISMISSED GDD_FINDING_EVENT_NAME=transition-dismissed
assert_status 0
assert_next feature-branch-review
printf 'Status: PASS\nFinding count: 0\n' >"$BRANCH_RESULT"
run_workflow "$PLAN_FILE" claim feature-branch-review branch-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active feature-branch-review PASS "$BRANCH_RESULT"
assert_status 0
assert_next feature-security-review
printf 'Status: FAIL\nFinding count: 0\n' >"$SECURITY_RESULT"
run_workflow "$PLAN_FILE" claim feature-security-review security-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active feature-security-review FAIL "$SECURITY_RESULT"
assert_status 0
run_workflow "$PLAN_FILE" claim finding-GDD-F0002-repair-finish-1 controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0002-repair-finish-1 RepairFinished "$EVIDENCE" GDD_FINDING_ID=GDD-F0002 GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Security Reviewer' GDD_FINDING_STATE=REPAIR_FINISH GDD_FINDING_EVENT_NAME=repair-finish GDD_REPAIR_ROUND=1 GDD_REPLAY_STATUS=VERIFIED
assert_status 0
assert_next finding-GDD-F0002-resolve
run_workflow "$PLAN_FILE" claim finding-GDD-F0002-resolve controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0002-resolve FindingResolved "$EVIDENCE" GDD_FINDING_ID=GDD-F0002 GDD_FINDING_SCOPE=feature GDD_FINDING_ORIGIN='Security Reviewer' GDD_FINDING_STATE=RESOLVED GDD_FINDING_EVENT_NAME=transition-resolved
assert_status 0
assert_next feature-security-review
printf 'Status: PASS\nFinding count: 0\n' >"$SECURITY_RESULT"
run_workflow "$PLAN_FILE" claim feature-security-review security-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active feature-security-review PASS "$SECURITY_RESULT"
assert_status 0
assert_next feature-findings-digest

# Spec D5 downstream: a worker observation resolves after the next worker PASS.
initialize_journal_fixture 'downstream-repair'
JOURNAL="$WORKSPACE/workflow-v1"
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: downstream repair.' >"$DISPATCH_FILE"
EVIDENCE="$REPO/evidence.md"
printf 'Status: DONE\n' >"$EVIDENCE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
downstream_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$downstream_receipt" PASS "$EVIDENCE"
assert_status 0
ROLE_RESULT="$REPO/role-result.md"
printf 'Status: PASS\nFinding count: 0\n' >"$ROLE_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-review task-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-review PASS "$ROLE_RESULT"
assert_status 0
CLEANER_FINDINGS="$REPO/cleaner-findings"
mkdir -p "$CLEANER_FINDINGS"
write_review_finding "$CLEANER_FINDINGS/1.md" Cleaner 'a duplicated helper' Minor
printf 'Status: PASS\nFinding count: 1\n' >"$ROLE_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-cleaner cleaner "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$CLEANER_FINDINGS" "$PLAN_FILE" accept-active slice-1-cleaner PASS "$ROLE_RESULT"
assert_status 0
assert_next finding-GDD-F0001-dispose
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-dispose controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-dispose FindingDispositionRecorded "$EVIDENCE" GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN=Cleaner GDD_FINDING_STATE=REPAIRING GDD_FINDING_EVENT_NAME=transition-repairing GDD_REPLAY_THROUGH=downstream
assert_status 0
assert_next finding-GDD-F0001-repair-start-1
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-start-1 fixer-max "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-repair-start-1 RepairStarted "$EVIDENCE" GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN=Cleaner GDD_FINDING_STATE=REPAIR_START GDD_FINDING_EVENT_NAME=repair-start GDD_REPAIR_ROUND=1
assert_status 0
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-result fixer-max "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-repair-result RepairAccepted "$EVIDENCE" GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN=Cleaner GDD_FINDING_STATE=REPAIR_RESULT GDD_FINDING_EVENT_NAME=repair-result GDD_REPAIR_ROUND=1 GDD_REPLAY_THROUGH=downstream
assert_status 0
downstream_invalidations=$(awk -F '\t' '$5 == "EvidenceInvalidated" { count++ } END { print count + 0 }' "$JOURNAL/events.tsv")
assert_equals 0 "$downstream_invalidations"
assert_next slice-1-architect
printf 'Status: PASS\nFinding count: 0\n' >"$ROLE_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-architect architect "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$FINDINGS_DIR" "$PLAN_FILE" accept-active slice-1-architect PASS "$ROLE_RESULT"
assert_status 0
assert_next finding-GDD-F0001-repair-finish-1

# Design D3 allows five slice repair rounds. A failed fourth round must begin
# round five, while a failed fifth round is capped before round six.
initialize_journal_fixture 'slice-round-five'
JOURNAL="$WORKSPACE/workflow-v1"
DISPATCH_FILE="$REPO/dispatch.md"
printf '%s\n' 'Dispatch: exercise slice repair rounds.' >"$DISPATCH_FILE"
EVIDENCE="$REPO/evidence.md"
printf 'Status: DONE\n' >"$EVIDENCE"
run_workflow "$PLAN_FILE" claim slice-1-implementer implementer "$DISPATCH_FILE"
assert_status 0
slice_round_receipt=$(extract_field 'Receipt')
run_workflow "$PLAN_FILE" accept "$slice_round_receipt" PASS "$EVIDENCE"
assert_status 0
SLICE_ROUND_FINDINGS="$REPO/slice-round-findings"
EMPTY_ROUND_FINDINGS="$REPO/empty-round-findings"
mkdir -p "$SLICE_ROUND_FINDINGS" "$EMPTY_ROUND_FINDINGS"
write_review_finding "$SLICE_ROUND_FINDINGS/1.md" 'Task Reviewer' 'the recurring defect'
REVIEW_RESULT="$REPO/review-result.md"
printf 'Status: FAIL\nFinding count: 1\n' >"$REVIEW_RESULT"
run_workflow "$PLAN_FILE" claim slice-1-review task-reviewer "$DISPATCH_FILE"
assert_status 0
run_grouped_workflow "$SLICE_ROUND_FINDINGS" "$PLAN_FILE" accept-active slice-1-review FAIL "$REVIEW_RESULT"
assert_status 0
run_workflow "$PLAN_FILE" claim finding-GDD-F0001-dispose controller "$DISPATCH_FILE"
assert_status 0
finding_accept finding-GDD-F0001-dispose FindingDispositionRecorded "$EVIDENCE" \
  GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
  GDD_FINDING_STATE=REPAIRING GDD_FINDING_EVENT_NAME=transition-repairing GDD_REPLAY_THROUGH=re-review
assert_status 0

for repair_round in 1 2 3 4 5; do
  assert_next "finding-GDD-F0001-repair-start-$repair_round"
  run_workflow "$PLAN_FILE" claim "finding-GDD-F0001-repair-start-$repair_round" fixer-max "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-GDD-F0001-repair-start-$repair_round" RepairStarted "$EVIDENCE" \
    GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
    GDD_FINDING_STATE=REPAIR_START GDD_FINDING_EVENT_NAME=repair-start GDD_REPAIR_ROUND="$repair_round"
  assert_status 0
  run_workflow "$PLAN_FILE" claim finding-GDD-F0001-repair-result fixer-max "$DISPATCH_FILE"
  assert_status 0
  finding_accept finding-GDD-F0001-repair-result RepairAccepted "$EVIDENCE" \
    GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
    GDD_FINDING_STATE=REPAIR_RESULT GDD_FINDING_EVENT_NAME=repair-result GDD_REPAIR_ROUND="$repair_round" GDD_REPLAY_THROUGH=re-review
  assert_status 0
  assert_next slice-1-review
  printf 'Status: FAIL\nFinding count: 0\n' >"$REVIEW_RESULT"
  run_workflow "$PLAN_FILE" claim slice-1-review re-reviewer "$DISPATCH_FILE"
  assert_status 0
  run_grouped_workflow "$EMPTY_ROUND_FINDINGS" "$PLAN_FILE" accept-active slice-1-review FAIL "$REVIEW_RESULT"
  assert_status 0
  assert_next "finding-GDD-F0001-repair-finish-$repair_round"
  run_workflow "$PLAN_FILE" claim "finding-GDD-F0001-repair-finish-$repair_round" controller "$DISPATCH_FILE"
  assert_status 0
  finding_accept "finding-GDD-F0001-repair-finish-$repair_round" RepairFinished "$EVIDENCE" \
    GDD_FINDING_ID=GDD-F0001 GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN='Task Reviewer' \
    GDD_FINDING_STATE=REPAIR_FINISH GDD_FINDING_EVENT_NAME=repair-finish GDD_REPAIR_ROUND="$repair_round" GDD_REPLAY_STATUS=FAILED
  assert_status 0
done
assert_next finding-GDD-F0001-dispose

if [ "$fail" -ne 0 ]; then
  printf '\n%d test(s) failed; %d passed\n' "$fail" "$pass" >&2
  exit 1
fi

printf '\n%d test(s) passed\n' "$pass"
