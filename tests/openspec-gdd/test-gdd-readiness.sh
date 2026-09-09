#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
READINESS="$REPO_ROOT/skills/gauntlet-driven-development/scripts/gdd-readiness"

FAILURES=0
STATUS=0
OUTPUT=""
FAIL_COUNT=0
TEST_ROOT="$(mktemp -d)"
VALID_REPO="$TEST_ROOT/valid-repo"
VALID_CHANGE="$VALID_REPO/openspec/changes/valid"

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

assert_contains() {
  local expected="$1"

  if printf '%s\n' "$OUTPUT" | grep -Fqx -- "$expected"; then
    pass "reports: $expected"
  else
    fail "reports: $expected"
    echo "    actual: $OUTPUT"
  fi
}

assert_fail_count() {
  local expected="$1"

  if [[ "$FAIL_COUNT" == "$expected" ]]; then
    pass "reports $expected failure(s)"
  else
    fail "reports $expected failure(s)"
    echo "    actual: $FAIL_COUNT"
  fi
}

assert_no_pass() {
  if printf '%s\n' "$OUTPUT" | grep -q '^PASS:'; then
    fail 'does not report PASS for malformed input'
    echo "    actual: $OUTPUT"
  else
    pass 'does not report PASS for malformed input'
  fi
}

run_readiness() {
  if OUTPUT="$("$READINESS" "$@" 2>&1)"; then
    STATUS=0
  else
    STATUS=$?
  fi

  FAIL_COUNT="$(printf '%s\n' "$OUTPUT" | awk '/^FAIL:/ { count++ } END { print count + 0 }')"
}

make_valid_change() {
  mkdir -p \
    "$VALID_CHANGE/specs/deployment" \
    "$VALID_REPO/features/openspec/valid"
  git -C "$VALID_REPO" init -q

  cat >"$VALID_CHANGE/.openspec.yaml" <<'EOF'
schema: superpowers-bridge
EOF

  cat >"$VALID_CHANGE/proposal.md" <<'EOF'
# Deploy one branch
EOF

  cat >"$VALID_CHANGE/design.md" <<'EOF'
# Deployment design
EOF

  cat >"$VALID_CHANGE/specs/deployment/spec.md" <<'EOF'
## ADDED Requirements

### Requirement: Deploy one branch

#### Scenario: Deploy succeeds

- **WHEN** the branch deploys
- **THEN** deployment succeeds
EOF

  cat >"$VALID_CHANGE/gherkin.md" <<'EOF'
# Gherkin mappings

`features/openspec/valid/deployment.feature`

deployment / Scenario 01
EOF

  cat >"$VALID_CHANGE/qa.md" <<'EOF'
# QA procedures

QA procedure 01
EOF

  cat >"$VALID_CHANGE/tasks.md" <<'EOF'
## 1. Deploy one branch

**Slice state:** [ ] QUEUED
**Executor:** implementer
**Gherkin scenarios:** deployment / Scenario 01
**QA procedures:** QA procedure 01

- [ ] 1.1 Add the behavior
- [ ] 1.V **Slice verification gate**
EOF

  cat >"$VALID_CHANGE/plan.md" <<'EOF'
## Task 1: Deploy one branch
EOF

  cat >"$VALID_CHANGE/plan-validator-verdict.md" <<'EOF'
**PASS WITH NOTES**
EOF

  cat >"$VALID_REPO/features/openspec/valid/deployment.feature" <<'EOF'
Feature: Deployment

  Scenario: Scenario 01
    Given a branch
    When it deploys
    Then deployment succeeds
EOF
}

copy_valid_change() {
  local fixture_name="$1"
  local fixture_repo="$TEST_ROOT/$fixture_name"

  cp -R "$VALID_REPO" "$fixture_repo"
  printf '%s\n' "$fixture_repo/openspec/changes/valid"
}

make_skill_fixture() {
  local fixture_name="$1"
  local fixture_root="$TEST_ROOT/$fixture_name-skills"
  local fixture_policy

  mkdir -p "$fixture_root"
  cp -R "$REPO_ROOT/skills/gauntlet-driven-development" "$fixture_root/"
  fixture_policy="$fixture_root/gauntlet-driven-development/finding-policy.md"
  cat >"$fixture_policy" <<'EOF'
# GDD finding policy
Policy-Version: 2
## Authority
## Finding report
## Finding states
## Adjudication
## Repair
## Astra
## Interruption
## Role gates
## Feature closing
EOF
  printf '%s\n' "$fixture_root/gauntlet-driven-development/scripts/gdd-readiness"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    sha256sum "$1" | awk '{ print $1 }'
  fi
}

echo "OpenSpec GDD readiness tests"

make_valid_change
VALID_CHANGE="$(cd "$VALID_CHANGE" && pwd -P)"

run_readiness "$VALID_CHANGE"
assert_status 0
assert_output "PASS: OpenSpec change is ready for GDD: $VALID_CHANGE"
assert_fail_count 0

ORIGINAL_READINESS="$READINESS"

READINESS="$(make_skill_fixture missing-workflow-state)"
rm "$(dirname "$READINESS")/gdd-workflow-state"
run_readiness "$VALID_CHANGE"
assert_status 1
assert_contains 'FAIL: GDD workflow state engine is missing or not executable'

READINESS="$(make_skill_fixture nonexecutable-workflow-state)"
chmod -x "$(dirname "$READINESS")/gdd-workflow-state"
run_readiness "$VALID_CHANGE"
assert_status 1
assert_contains 'FAIL: GDD workflow state engine is missing or not executable'

READINESS="$(make_skill_fixture unsupported-workflow-format)"
cat >"$(dirname "$READINESS")/gdd-workflow-state" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 1
EOF
chmod +x "$(dirname "$READINESS")/gdd-workflow-state"
run_readiness "$VALID_CHANGE"
assert_status 1
assert_contains 'FAIL: GDD workflow state engine reports unsupported format version: 1'

READINESS="$(make_skill_fixture missing-finding-policy)"
rm -f "$(dirname "$READINESS")/../finding-policy.md"
run_readiness "$VALID_CHANGE"
assert_status 1
assert_contains 'FAIL: GDD finding policy is missing or empty'

READINESS="$(make_skill_fixture malformed-finding-policy)"
sed -i.bak '/^Policy-Version:/d' "$(dirname "$READINESS")/../finding-policy.md"
rm "$(dirname "$READINESS")/../finding-policy.md.bak"
run_readiness "$VALID_CHANGE"
assert_status 1
assert_contains 'FAIL: GDD finding policy must contain exactly one Policy-Version: 2'

READINESS="$(make_skill_fixture missing-policy-section)"
sed -i.bak '/^## Astra$/d' "$(dirname "$READINESS")/../finding-policy.md"
rm "$(dirname "$READINESS")/../finding-policy.md.bak"
run_readiness "$VALID_CHANGE"
assert_status 1
assert_contains 'FAIL: GDD finding policy is malformed: ## Astra'

READINESS="$(make_skill_fixture pinned-run-ignores-installed-drift)"
PINNED_CHANGE="$(copy_valid_change pinned-run-ignores-installed-drift)"
PINNED_REPO="$(git -C "$PINNED_CHANGE" rev-parse --show-toplevel)"
PINNED_WORKSPACE="$PINNED_REPO/.superpowers/gdd/valid"
mkdir -p "$PINNED_WORKSPACE"
cp "$(dirname "$READINESS")/../finding-policy.md" \
  "$PINNED_WORKSPACE/finding-policy.md"
sha256_file "$PINNED_WORKSPACE/finding-policy.md" \
  >"$PINNED_WORKSPACE/finding-policy.sha256"
sed -i.bak '/^## Astra$/d' "$(dirname "$READINESS")/../finding-policy.md"
rm "$(dirname "$READINESS")/../finding-policy.md.bak"
run_readiness "$PINNED_CHANGE"
assert_status 0

printf '\nTampered snapshot.\n' >>"$PINNED_WORKSPACE/finding-policy.md"
run_readiness "$PINNED_CHANGE"
assert_status 1
assert_contains 'FAIL: saved GDD finding policy snapshot does not match its recorded digest'

READINESS="$ORIGINAL_READINESS"

run_readiness
assert_status 2
assert_output 'usage: gdd-readiness CHANGE_DIRECTORY'

SCHEMA_CHANGE="$(copy_valid_change bad-schema)"
printf 'schema: spec-driven\n' >"$SCHEMA_CHANGE/.openspec.yaml"
run_readiness "$SCHEMA_CHANGE"
assert_status 1
assert_contains 'FAIL: .openspec.yaml must select schema: superpowers-bridge'
assert_no_pass

MIXED_SCHEMA_CHANGE="$(copy_valid_change mixed-schema)"
printf 'schema: superpowers-bridge\nschema: spec-driven\n' \
  >"$MIXED_SCHEMA_CHANGE/.openspec.yaml"
run_readiness "$MIXED_SCHEMA_CHANGE"
assert_status 1
assert_contains 'FAIL: .openspec.yaml must select schema: superpowers-bridge'
assert_fail_count 1
assert_no_pass

MISSING_PLAN_CHANGE="$(copy_valid_change missing-plan)"
rm "$MISSING_PLAN_CHANGE/plan.md"
run_readiness "$MISSING_PLAN_CHANGE"
assert_status 1
assert_contains 'FAIL: required artifact is missing or empty: plan.md'
assert_fail_count 1
assert_no_pass

MISSING_MAPPING_CHANGE="$(copy_valid_change missing-mappings)"
rm "$MISSING_MAPPING_CHANGE/gherkin.md" "$MISSING_MAPPING_CHANGE/qa.md"
run_readiness "$MISSING_MAPPING_CHANGE"
assert_status 1
assert_contains 'FAIL: required artifact is missing or empty: gherkin.md'
assert_contains 'FAIL: required artifact is missing or empty: qa.md'
assert_fail_count 2
assert_no_pass

MISSING_SPEC_CHANGE="$(copy_valid_change missing-spec)"
rm "$MISSING_SPEC_CHANGE/specs/deployment/spec.md"
run_readiness "$MISSING_SPEC_CHANGE"
assert_status 1
assert_contains 'FAIL: no nonempty delta spec found under specs/*/spec.md'
assert_no_pass

MISSING_FEATURE_CHANGE="$(copy_valid_change missing-feature)"
rm "$TEST_ROOT/missing-feature/features/openspec/valid/deployment.feature"
run_readiness "$MISSING_FEATURE_CHANGE"
assert_status 1
assert_contains 'FAIL: mapped Gherkin feature is missing: features/openspec/valid/deployment.feature'
assert_no_pass

SYMLINK_ESCAPE_CHANGE="$(copy_valid_change symlink-escape)"
mkdir -p "$TEST_ROOT/outside-feature-directory"
printf 'Feature: Outside repository\n' >"$TEST_ROOT/outside-feature-directory/deployment.feature"
rm -r "$TEST_ROOT/symlink-escape/features/openspec/valid"
ln -s "$TEST_ROOT/outside-feature-directory" \
  "$TEST_ROOT/symlink-escape/features/openspec/valid"
run_readiness "$SYMLINK_ESCAPE_CHANGE"
assert_status 1
assert_contains 'FAIL: mapped Gherkin feature is not repository-relative: features/openspec/valid/deployment.feature'
assert_fail_count 1
assert_no_pass

FILE_SYMLINK_ESCAPE_CHANGE="$(copy_valid_change file-symlink-escape)"
printf 'Feature: Outside repository\n' >"$TEST_ROOT/outside-feature.file"
rm "$TEST_ROOT/file-symlink-escape/features/openspec/valid/deployment.feature"
ln -s "$TEST_ROOT/outside-feature.file" \
  "$TEST_ROOT/file-symlink-escape/features/openspec/valid/deployment.feature"
run_readiness "$FILE_SYMLINK_ESCAPE_CHANGE"
assert_status 1
assert_contains 'FAIL: mapped Gherkin feature is not repository-relative: features/openspec/valid/deployment.feature'
assert_fail_count 1
assert_no_pass

MISSING_SLICE_FIELDS_CHANGE="$(copy_valid_change missing-slice-fields)"
awk '!/^\*\*(Slice state|Executor|Gherkin scenarios|QA procedures):/ && !/^- \[ \] 1\.V/' \
  "$MISSING_SLICE_FIELDS_CHANGE/tasks.md" >"$TEST_ROOT/missing-slice-fields/tasks.md.tmp"
mv "$TEST_ROOT/missing-slice-fields/tasks.md.tmp" "$MISSING_SLICE_FIELDS_CHANGE/tasks.md"
run_readiness "$MISSING_SLICE_FIELDS_CHANGE"
assert_status 1
assert_contains 'FAIL: tasks.md slice 1 must contain exactly one queued Slice state'
assert_contains 'FAIL: tasks.md slice 1 must contain exactly one unchecked 1.V Slice verification gate'
assert_contains 'FAIL: tasks.md slice 1 must contain exactly one nonempty Executor'
assert_contains 'FAIL: tasks.md slice 1 must contain exactly one nonempty Gherkin scenarios label'
assert_contains 'FAIL: tasks.md slice 1 must contain exactly one nonempty QA procedures label'
assert_fail_count 5
assert_no_pass

DUPLICATE_EXECUTOR_CHANGE="$(copy_valid_change duplicate-executor)"
awk '{ print; if ($0 == "**Executor:** implementer") print "**Executor:**" }' \
  "$DUPLICATE_EXECUTOR_CHANGE/tasks.md" >"$TEST_ROOT/duplicate-executor/tasks.md.tmp"
mv "$TEST_ROOT/duplicate-executor/tasks.md.tmp" "$DUPLICATE_EXECUTOR_CHANGE/tasks.md"
run_readiness "$DUPLICATE_EXECUTOR_CHANGE"
assert_status 1
assert_contains 'FAIL: tasks.md slice 1 must contain exactly one nonempty Executor'
assert_fail_count 1
assert_no_pass

DUPLICATE_GHERKIN_CHANGE="$(copy_valid_change duplicate-gherkin)"
awk '{ print; if ($0 == "**Gherkin scenarios:** deployment / Scenario 01") print "**Gherkin scenarios:**" }' \
  "$DUPLICATE_GHERKIN_CHANGE/tasks.md" >"$TEST_ROOT/duplicate-gherkin/tasks.md.tmp"
mv "$TEST_ROOT/duplicate-gherkin/tasks.md.tmp" "$DUPLICATE_GHERKIN_CHANGE/tasks.md"
run_readiness "$DUPLICATE_GHERKIN_CHANGE"
assert_status 1
assert_contains 'FAIL: tasks.md slice 1 must contain exactly one nonempty Gherkin scenarios label'
assert_fail_count 1
assert_no_pass

DUPLICATE_QA_CHANGE="$(copy_valid_change duplicate-qa)"
awk '{ print; if ($0 == "**QA procedures:** QA procedure 01") print "**QA procedures:**" }' \
  "$DUPLICATE_QA_CHANGE/tasks.md" >"$TEST_ROOT/duplicate-qa/tasks.md.tmp"
mv "$TEST_ROOT/duplicate-qa/tasks.md.tmp" "$DUPLICATE_QA_CHANGE/tasks.md"
run_readiness "$DUPLICATE_QA_CHANGE"
assert_status 1
assert_contains 'FAIL: tasks.md slice 1 must contain exactly one nonempty QA procedures label'
assert_fail_count 1
assert_no_pass

UNRESOLVED_REFERENCES_CHANGE="$(copy_valid_change unresolved-references)"
awk '{ sub(/deployment \/ Scenario 01/, "missing scenario"); print }' \
  "$UNRESOLVED_REFERENCES_CHANGE/tasks.md" >"$TEST_ROOT/unresolved-references/tasks.md.tmp"
mv "$TEST_ROOT/unresolved-references/tasks.md.tmp" "$UNRESOLVED_REFERENCES_CHANGE/tasks.md"
awk '{ sub(/QA procedure 01/, "missing procedure"); print }' \
  "$UNRESOLVED_REFERENCES_CHANGE/tasks.md" >"$TEST_ROOT/unresolved-references/tasks.md.tmp"
mv "$TEST_ROOT/unresolved-references/tasks.md.tmp" "$UNRESOLVED_REFERENCES_CHANGE/tasks.md"
run_readiness "$UNRESOLVED_REFERENCES_CHANGE"
assert_status 1
assert_contains 'FAIL: tasks.md slice 1 Gherkin scenarios reference is unresolved: missing scenario'
assert_contains 'FAIL: tasks.md slice 1 QA procedures reference is unresolved: missing procedure'
assert_fail_count 2
assert_no_pass

PREFIX_COLLISION_CHANGE="$(copy_valid_change prefix-collision)"
awk '{ sub(/deployment \/ Scenario 01/, "deployment / Scenario 0"); print }' \
  "$PREFIX_COLLISION_CHANGE/tasks.md" >"$TEST_ROOT/prefix-collision/tasks.md.tmp"
mv "$TEST_ROOT/prefix-collision/tasks.md.tmp" "$PREFIX_COLLISION_CHANGE/tasks.md"
run_readiness "$PREFIX_COLLISION_CHANGE"
assert_status 1
assert_contains 'FAIL: tasks.md slice 1 Gherkin scenarios reference is unresolved: deployment / Scenario 0'
assert_fail_count 1
assert_no_pass

MISMATCHED_PLAN_CHANGE="$(copy_valid_change mismatched-plan)"
awk '{ sub(/## Task 1:/, "## Task 2:"); print }' \
  "$MISMATCHED_PLAN_CHANGE/plan.md" >"$TEST_ROOT/mismatched-plan/plan.md.tmp"
mv "$TEST_ROOT/mismatched-plan/plan.md.tmp" "$MISMATCHED_PLAN_CHANGE/plan.md"
run_readiness "$MISMATCHED_PLAN_CHANGE"
assert_status 1
assert_contains 'FAIL: tasks.md slice 1 has no matching plan.md Task 1 section'
assert_contains 'FAIL: plan.md Task 2 has no matching tasks.md slice 2'
assert_fail_count 2
assert_no_pass

MISSING_VERDICT_CHANGE="$(copy_valid_change missing-verdict)"
rm "$MISSING_VERDICT_CHANGE/plan-validator-verdict.md"
run_readiness "$MISSING_VERDICT_CHANGE"
assert_status 1
assert_contains 'FAIL: required artifact is missing or empty: plan-validator-verdict.md'
assert_no_pass

EMPTY_HANDOFF_CHANGE="$(copy_valid_change empty-handoff)"
printf '# No task slices\n' >"$EMPTY_HANDOFF_CHANGE/tasks.md"
printf '# No plan tasks\n' >"$EMPTY_HANDOFF_CHANGE/plan.md"
run_readiness "$EMPTY_HANDOFF_CHANGE"
assert_status 1
assert_contains 'FAIL: no recognized task slices'
assert_contains 'FAIL: no recognized plan tasks'
assert_fail_count 2
assert_no_pass

NO_TASK_SLICES_CHANGE="$(copy_valid_change no-task-slices)"
printf '# No task slices\n' >"$NO_TASK_SLICES_CHANGE/tasks.md"
run_readiness "$NO_TASK_SLICES_CHANGE"
assert_status 1
assert_contains 'FAIL: no recognized task slices'
assert_fail_count 1
assert_no_pass

NO_PLAN_TASKS_CHANGE="$(copy_valid_change no-plan-tasks)"
printf '# No plan tasks\n' >"$NO_PLAN_TASKS_CHANGE/plan.md"
run_readiness "$NO_PLAN_TASKS_CHANGE"
assert_status 1
assert_contains 'FAIL: no recognized plan tasks'
assert_fail_count 1
assert_no_pass

FAILING_VERDICT_CHANGE="$(copy_valid_change failing-verdict)"
printf 'CHANGES REQUIRED\n' >"$FAILING_VERDICT_CHANGE/plan-validator-verdict.md"
run_readiness "$FAILING_VERDICT_CHANGE"
assert_status 1
assert_contains 'FAIL: plan-validator verdict does not pass'
assert_no_pass

MALFORMED_PASS_VERDICT_CHANGE="$(copy_valid_change malformed-pass-verdict)"
printf '**PASS\n' >"$MALFORMED_PASS_VERDICT_CHANGE/plan-validator-verdict.md"
run_readiness "$MALFORMED_PASS_VERDICT_CHANGE"
assert_status 1
assert_contains 'FAIL: plan-validator verdict does not pass'
assert_fail_count 1
assert_no_pass

BALANCED_PASS_VERDICT_CHANGE="$(copy_valid_change balanced-pass-verdict)"
printf '**PASS**\n' >"$BALANCED_PASS_VERDICT_CHANGE/plan-validator-verdict.md"
run_readiness "$BALANCED_PASS_VERDICT_CHANGE"
assert_status 0
assert_fail_count 0

PERIOD_PASS_VERDICT_CHANGE="$(copy_valid_change period-pass-verdict)"
printf 'PASS.\n' >"$PERIOD_PASS_VERDICT_CHANGE/plan-validator-verdict.md"
run_readiness "$PERIOD_PASS_VERDICT_CHANGE"
assert_status 0
assert_fail_count 0

COLON_PASS_VERDICT_CHANGE="$(copy_valid_change colon-pass-verdict)"
printf 'PASS WITH NOTES:\n' >"$COLON_PASS_VERDICT_CHANGE/plan-validator-verdict.md"
run_readiness "$COLON_PASS_VERDICT_CHANGE"
assert_status 0
assert_fail_count 0

DECORATED_PERIOD_PASS_VERDICT_CHANGE="$(copy_valid_change decorated-period-pass-verdict)"
printf '**PASS.**\n' >"$DECORATED_PERIOD_PASS_VERDICT_CHANGE/plan-validator-verdict.md"
run_readiness "$DECORATED_PERIOD_PASS_VERDICT_CHANGE"
assert_status 0
assert_fail_count 0

DECORATED_COLON_PASS_VERDICT_CHANGE="$(copy_valid_change decorated-colon-pass-verdict)"
printf '**PASS WITH NOTES:**\n' >"$DECORATED_COLON_PASS_VERDICT_CHANGE/plan-validator-verdict.md"
run_readiness "$DECORATED_COLON_PASS_VERDICT_CHANGE"
assert_status 0
assert_fail_count 0

PROSE_VERDICT_CHANGE="$(copy_valid_change prose-verdict)"
printf 'The plan validator passed its checks.\n' >"$PROSE_VERDICT_CHANGE/plan-validator-verdict.md"
run_readiness "$PROSE_VERDICT_CHANGE"
assert_status 1
assert_contains 'FAIL: plan-validator verdict does not pass'
assert_no_pass

if [[ "$FAILURES" -eq 0 ]]; then
  echo "All OpenSpec GDD readiness tests passed"
else
  echo "$FAILURES OpenSpec GDD readiness test(s) failed"
  exit 1
fi
