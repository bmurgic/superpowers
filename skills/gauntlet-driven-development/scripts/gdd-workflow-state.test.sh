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
WORKFLOW="$RUNTIME_ROOT/scripts/gdd-workflow-state"

make_fixture 'journal-init'

# Break caught: omitting v1 workspace initialization leaves the lifecycle without durable state.
run_workflow "$PLAN_FILE" init
assert_status 0
assert_file "$WORKSPACE/workflow-v1/format-version"
assert_file_contains "$WORKSPACE/workflow-v1/format-version" '1'
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
printf '%s\n' 2 >"$JOURNAL/format-version"

# Break caught: an unknown journal version must be rejected by the reducer, not a preflight shortcut.
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains INVALID
assert_output_contains 'workflow format version is unknown: 2'

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
printf '%s\n' 'Status: PASS' >"$RESULT_FILE"
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

initialize_journal_fixture 'stale-claim-revision'
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/result.md"
printf '%s\n' 'Dispatch: stale revision check.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: PASS' >"$RESULT_FILE"
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
assert_output_contains '1'
assert_not_exists "$staged_transaction"
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains 'Resume claim: slice-1-implementer'

initialize_journal_fixture 'repair-invalidation'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/implementer.md' 'initial implementer evidence'
write_event_evidence "$JOURNAL" 'events/cleaner.md' 'initial cleaner evidence'
implementer_digest=$(sha256_file "$JOURNAL/events/implementer.md")
cleaner_digest=$(sha256_file "$JOURNAL/events/cleaner.md")
append_event "$JOURNAL" 1 1 event-1 slice-1-implementer ACCEPT implementer receipt-implementer events/implementer.md "$implementer_digest" -
implementer_event_hash=$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')
append_event "$JOURNAL" 2 2 event-2 slice-1-cleaner ACCEPT cleaner receipt-cleaner events/cleaner.md "$cleaner_digest" "$implementer_event_hash"
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/result.md"
printf '%s\n' 'Dispatch: repair the architect finding.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: PASS' >"$RESULT_FILE"
run_workflow "$PLAN_FILE" claim slice-1-architect fixer "$DISPATCH_FILE"
assert_status 0
repair_receipt=$(extract_field 'Receipt')

# Break caught: accepting a repair must append the replay-table invalidations rather than relying on a caller-written event.
run_workflow "$PLAN_FILE" accept "$repair_receipt" PASS "$RESULT_FILE"
assert_status 0
invalidated_obligations=$(awk -F '\t' '$5 == "EvidenceInvalidated" { print $4 }' "$JOURNAL/events.tsv" | paste -sd, -)
assert_equals 'slice-1-cleaner,slice-1-architect' "$invalidated_obligations"
run_workflow "$PLAN_FILE" next
assert_status 0
assert_output_contains 'slice-1-cleaner'

initialize_journal_fixture 'interrupted-repair-acceptance'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/implementer.md' 'initial implementer evidence'
write_event_evidence "$JOURNAL" 'events/cleaner.md' 'initial cleaner evidence'
implementer_digest=$(sha256_file "$JOURNAL/events/implementer.md")
cleaner_digest=$(sha256_file "$JOURNAL/events/cleaner.md")
append_event "$JOURNAL" 1 1 event-1 slice-1-implementer ACCEPT implementer receipt-implementer events/implementer.md "$implementer_digest" -
implementer_event_hash=$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')
append_event "$JOURNAL" 2 2 event-2 slice-1-cleaner ACCEPT cleaner receipt-cleaner events/cleaner.md "$cleaner_digest" "$implementer_event_hash"
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/result.md"
printf '%s\n' 'Dispatch: repair the architect finding.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: PASS' >"$RESULT_FILE"
run_workflow "$PLAN_FILE" claim slice-1-architect fixer "$DISPATCH_FILE"
assert_status 0
repair_receipt=$(extract_field 'Receipt')

# Break caught: recovery must not publish a repair ACCEPT without every ordered replay invalidation.
run_interrupted_workflow "$PLAN_FILE" accept "$repair_receipt" PASS "$RESULT_FILE"
assert_status 75
run_workflow "$PLAN_FILE" status
assert_status 0
invalidated_obligations=$(awk -F '\t' '$5 == "EvidenceInvalidated" { print $4 }' "$JOURNAL/events.tsv" | paste -sd, -)
assert_equals 'slice-1-cleaner,slice-1-architect' "$invalidated_obligations"

initialize_journal_fixture 'partial-repair-evidence-publication'
JOURNAL="$WORKSPACE/workflow-v1"
write_event_evidence "$JOURNAL" 'events/implementer.md' 'initial implementer evidence'
write_event_evidence "$JOURNAL" 'events/cleaner.md' 'initial cleaner evidence'
implementer_digest=$(sha256_file "$JOURNAL/events/implementer.md")
cleaner_digest=$(sha256_file "$JOURNAL/events/cleaner.md")
append_event "$JOURNAL" 1 1 event-1 slice-1-implementer ACCEPT implementer receipt-implementer events/implementer.md "$implementer_digest" -
implementer_event_hash=$(tail -n 1 "$JOURNAL/events.tsv" | awk -F '\t' '{ print $11 }')
append_event "$JOURNAL" 2 2 event-2 slice-1-cleaner ACCEPT cleaner receipt-cleaner events/cleaner.md "$cleaner_digest" "$implementer_event_hash"
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/result.md"
printf '%s\n' 'Dispatch: repair the architect finding.' >"$DISPATCH_FILE"
printf '%s\n' 'Status: PASS' >"$RESULT_FILE"
run_workflow "$PLAN_FILE" claim slice-1-architect fixer "$DISPATCH_FILE"
assert_status 0
repair_receipt=$(extract_field 'Receipt')

# Break caught: recovery must not move the grouped journal over a partially visible invalidation directory.
run_publication_interrupted_workflow "$PLAN_FILE" accept "$repair_receipt" PASS "$RESULT_FILE"
assert_status 76
assert_file "$JOURNAL/events/event-5/metadata.tsv"
run_workflow "$PLAN_FILE" status
assert_status 0
invalidated_obligations=$(awk -F '\t' '$5 == "EvidenceInvalidated" { print $4 }' "$JOURNAL/events.tsv" | paste -sd, -)
assert_equals 'slice-1-cleaner,slice-1-architect' "$invalidated_obligations"

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
printf '%s\n' 'Status: PASS' >"$RESULT_FILE"
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
assert_file_contains "$CHANGE/tasks.md" '**Slice state:** [~] VERIFYING: CLEANER'

initialize_journal_fixture 'finding-side-event'
DISPATCH_FILE="$REPO/dispatch.md"
RESULT_FILE="$REPO/finding.md"
printf '%s\n' 'Dispatch: collect Cleaner findings.' >"$DISPATCH_FILE"
printf '%s\n' 'Origin role: Cleaner' >"$RESULT_FILE"
run_workflow "$PLAN_FILE" claim slice-1-implementer cleaner "$DISPATCH_FILE"
assert_status 0
output=$(GDD_FINDING_SCOPE=1 GDD_FINDING_ORIGIN=Cleaner GDD_REPORT_COMPLETE=no \
  "$WORKFLOW" "$PLAN_FILE" accept-active slice-1-implementer FindingReported "$RESULT_FILE" 2>&1)
status=$?
assert_status 0
assert_output_contains 'Finding ID: GDD-F0001'
run_workflow "$PLAN_FILE" status
assert_status 0
assert_output_contains 'Active claim: slice-1-implementer'
assert_output_contains 'finding-GDD-F0001-supplement READY'
assert_file_contains "$WORKSPACE/workflow-v1/events/event-2/metadata.tsv" $'finding-origin\tCleaner'

# Break caught: typed finding metadata must be covered by the event hash, not mutable projection input.
printf '%s\n' $'finding-origin\tArchitect' >>"$WORKSPACE/workflow-v1/events/event-2/metadata.tsv"
run_workflow "$PLAN_FILE" status
assert_status 1
assert_output_contains 'broken event hash at sequence 2'

if [ "$fail" -ne 0 ]; then
  printf '\n%d test(s) failed; %d passed\n' "$fail" "$pass" >&2
  exit 1
fi

printf '\n%d test(s) passed\n' "$pass"
