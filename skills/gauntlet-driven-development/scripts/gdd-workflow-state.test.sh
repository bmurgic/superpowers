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

if [ "$fail" -ne 0 ]; then
  printf '\n%d test(s) failed; %d passed\n' "$fail" "$pass" >&2
  exit 1
fi

printf '\n%d test(s) passed\n' "$pass"
