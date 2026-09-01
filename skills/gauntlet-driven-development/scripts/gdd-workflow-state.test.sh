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
