#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/skills/openspec-gdd/scripts/require-bridge-schema"

FAILURES=0
STATUS=0
OUTPUT=""
SCHEMA_FIXTURE=""
TEST_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

pass() {
  echo "  [PASS] $1"
}

fail() {
  echo "  [FAIL] $1"
  FAILURES=$((FAILURES + 1))
}

assert_status() {
  local expected="$1"

  if [[ "$STATUS" == "$expected" ]]; then
    pass "exits with status $expected"
  else
    fail "exits with status $expected"
    echo "    actual: $STATUS"
  fi
}

assert_output() {
  local expected="$1"

  if [[ "$OUTPUT" == "$expected" ]]; then
    pass "reports: $expected"
  else
    fail "reports: $expected"
    echo "    actual: $OUTPUT"
  fi
}

assert_output_line_count() {
  local expected="$1"
  local actual

  actual="$(printf '%s\n' "$OUTPUT" | awk 'END { print NR }')"
  if [[ "$actual" == "$expected" ]]; then
    pass "reports $expected output line(s)"
  else
    fail "reports $expected output line(s)"
    echo "    actual: $actual"
  fi
}

run_guard() {
  if OUTPUT="$(
    PATH="$TEST_ROOT/fake-bin:$PATH" \
      OPEN_SPEC_SCHEMA_FIXTURE="$TEST_ROOT/fixtures/$SCHEMA_FIXTURE" \
      "$GUARD" "$@" 2>&1
  )"; then
    STATUS=0
  else
    STATUS=$?
  fi
}

run_guard_without_fake() {
  if OUTPUT="$(PATH="$TEST_ROOT/empty-bin:/usr/bin:/bin" "$GUARD" 2>&1)"; then
    STATUS=0
  else
    STATUS=$?
  fi
}

write_fake_openspec() {
  cat >"$TEST_ROOT/fake-bin/openspec" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${OPEN_SPEC_SCHEMA_STATUS:-}" ]]; then
  if [[ -n "${OPEN_SPEC_SCHEMA_STDERR:-}" ]]; then
    printf '%s\n' "$OPEN_SPEC_SCHEMA_STDERR" >&2
  fi
  exit "$OPEN_SPEC_SCHEMA_STATUS"
fi

cat "$OPEN_SPEC_SCHEMA_FIXTURE"
EOF
  chmod +x "$TEST_ROOT/fake-bin/openspec"
}

write_fixtures() {
  cat >"$TEST_ROOT/fixtures/bridge.json" <<'EOF'
[
  { "name": "spec-driven" },
  { "name": "superpowers-bridge" }
]
EOF

  cat >"$TEST_ROOT/fixtures/default-only.json" <<'EOF'
[
  { "name": "spec-driven" }
]
EOF
}

echo "OpenSpec GDD bridge schema guard tests"

mkdir -p "$TEST_ROOT/empty-bin" "$TEST_ROOT/fake-bin" "$TEST_ROOT/fixtures"
write_fake_openspec
write_fixtures

SCHEMA_FIXTURE=bridge.json
run_guard
assert_status 0
assert_output 'PASS: OpenSpec schema superpowers-bridge is installed'

run_guard unexpected
assert_status 2
assert_output 'usage: require-bridge-schema'

SCHEMA_FIXTURE=default-only.json
run_guard
assert_status 1
assert_output 'FAIL: OpenSpec schema superpowers-bridge is not installed'

SCHEMA_FIXTURE=bridge.json
OPEN_SPEC_SCHEMA_STDERR='raw openspec discovery error' \
  OPEN_SPEC_SCHEMA_STATUS=7 \
  run_guard
assert_status 1
assert_output 'FAIL: could not list OpenSpec schemas'
assert_output_line_count 1

PATH="$TEST_ROOT/empty-bin:/usr/bin:/bin" run_guard_without_fake
assert_status 1
assert_output 'FAIL: openspec is not available on PATH'

if [[ "$FAILURES" -eq 0 ]]; then
  echo "All OpenSpec GDD bridge schema guard tests passed"
else
  echo "$FAILURES OpenSpec GDD bridge schema guard test(s) failed"
  exit 1
fi
