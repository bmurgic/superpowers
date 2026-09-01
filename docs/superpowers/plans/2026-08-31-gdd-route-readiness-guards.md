# OpenSpec GDD Route and Readiness Guards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent an OpenSpec GDD selection from silently becoming a standard OpenSpec change or reaching implementation without the bridge-owned planning artifacts.

**Architecture:** Add a dedicated `openspec-gdd` route skill with a pre-creation schema guard. Add one read-only `gdd-readiness CHANGE_DIRECTORY` verifier under the GDD skill and require it both after OpenSpec planning and before GDD setup.

**Tech Stack:** Bash 3.2-compatible shell, `awk`, `grep`, `find`, Git, OpenSpec CLI, Markdown skill files, existing shell and packaging tests.

**Spec:** `docs/superpowers/specs/2026-08-31-gdd-route-readiness-guards-design.md`

## Global Constraints

- Do not change the `superpowers-bridge` schema or OpenSpec.
- Do not add runtime dependencies or a general Markdown/YAML parser.
- Ordinary `spec-driven` changes remain valid OpenSpec changes but never pass GDD readiness.
- Both guards are read-only and fail closed with stable messages.
- Only a passing `plan-validator-verdict.md` permits the normal GDD-ready claim.
- GDD does not fall back to stock Subagent-Driven Development.
- Follow `superpowers:test-driven-development` for scripts and `superpowers:writing-skills` for every skill edit.
- Preserve the repository's Bash 3.2 compatibility and existing skill voice.
- Do not modify the unrelated linked-worktree restriction in `scripts/package-codex-plugin.sh`.

---

## File Map

- Create `tests/openspec-gdd/test-require-bridge-schema.sh`
  - Exercise schema discovery through a controlled fake OpenSpec executable.
- Create `skills/openspec-gdd/scripts/require-bridge-schema`
  - Prove the OpenSpec CLI can discover `superpowers-bridge` before change creation.
- Create `tests/openspec-gdd/test-gdd-readiness.sh`
  - Build complete and malformed OpenSpec change fixtures and assert the readiness contract.
- Create `skills/gauntlet-driven-development/scripts/gdd-readiness`
  - Validate one change directory and accumulate independent readiness defects.
- Create `skills/openspec-gdd/SKILL.md`
  - Own OpenSpec GDD route entry, explicit change creation, and the readiness claim.
- Create `skills/openspec-gdd/agents/openai.yaml`
  - Expose the new route skill to Codex packaging.
- Modify `skills/brainstorming/SKILL.md`
  - Route OpenSpec GDD through `openspec-gdd`.
- Modify `skills/gauntlet-driven-development/SKILL.md`
  - Run `gdd-readiness` before any setup or slice mutation.
- Modify `tests/personal-fork/test-personal-fork.sh`
  - Assert the three skills are wired to the same route and readiness contract.

### Task 1: Reject Missing OpenSpec Bridge Schemas Before Change Creation

**Files:**

- Create: `tests/openspec-gdd/test-require-bridge-schema.sh`
- Create: `skills/openspec-gdd/scripts/require-bridge-schema`

**Interfaces:**

- Consumes: `openspec schemas --json` on `PATH`.
- Produces: `require-bridge-schema` with exit 0 and one `PASS:` line when the schema exists, exit 1 and one `FAIL:` line for discovery failures, and exit 2 for arguments.

- [ ] **Step 1: Add the schema-guard behavioral test**

Create `tests/openspec-gdd/test-require-bridge-schema.sh` with a temporary fake
`openspec` that reads `OPEN_SPEC_SCHEMA_FIXTURE` and optionally exits with
`OPEN_SPEC_SCHEMA_STATUS`. Cover these cases:

```bash
run_guard bridge.json
assert_status 0
assert_output 'PASS: OpenSpec schema superpowers-bridge is installed'

run_guard default-only.json
assert_status 1
assert_output 'FAIL: OpenSpec schema superpowers-bridge is not installed'

OPEN_SPEC_SCHEMA_STATUS=7 run_guard bridge.json
assert_status 1
assert_output 'FAIL: could not list OpenSpec schemas'

PATH="$TEST_ROOT/empty-bin:/usr/bin:/bin" run_guard_without_fake
assert_status 1
assert_output 'FAIL: openspec is not available on PATH'
```

The bridge fixture includes both `spec-driven` and `superpowers-bridge`. The
default-only fixture matches the observed repository output and includes only
`spec-driven`.

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/openspec-gdd/test-require-bridge-schema.sh
```

Expected: FAIL because
`skills/openspec-gdd/scripts/require-bridge-schema` does not exist.

- [ ] **Step 3: Implement the minimal schema guard**

Create the executable script with this behavior:

```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo 'usage: require-bridge-schema' >&2
  exit 2
fi

if ! command -v openspec >/dev/null 2>&1; then
  echo 'FAIL: openspec is not available on PATH' >&2
  exit 1
fi

if ! schemas="$(openspec schemas --json)"; then
  echo 'FAIL: could not list OpenSpec schemas' >&2
  exit 1
fi

if ! printf '%s\n' "$schemas" \
  | grep -Eq '"name"[[:space:]]*:[[:space:]]*"superpowers-bridge"'; then
  echo 'FAIL: OpenSpec schema superpowers-bridge is not installed' >&2
  exit 1
fi

echo 'PASS: OpenSpec schema superpowers-bridge is installed'
```

Use `chmod +x` on the new script.

- [ ] **Step 4: Run focused GREEN verification**

Run:

```bash
bash tests/openspec-gdd/test-require-bridge-schema.sh
scripts/lint-shell.sh \
  tests/openspec-gdd/test-require-bridge-schema.sh \
  skills/openspec-gdd/scripts/require-bridge-schema
```

Expected: the behavioral suite passes and shell lint reports no errors.

- [ ] **Step 5: Commit the schema guard**

Run:

```bash
git add \
  tests/openspec-gdd/test-require-bridge-schema.sh \
  skills/openspec-gdd/scripts/require-bridge-schema
git commit -m "feat: guard the OpenSpec GDD schema"
```

Expected: one commit containing only the schema guard and its test.

### Task 2: Enforce the Complete GDD Planning Handoff

**Files:**

- Create: `tests/openspec-gdd/test-gdd-readiness.sh`
- Create: `skills/gauntlet-driven-development/scripts/gdd-readiness`

**Interfaces:**

- Consumes: one OpenSpec change directory at
  `<repo>/openspec/changes/<change-name>`.
- Produces: `gdd-readiness CHANGE_DIRECTORY`; exit 0 with one `PASS:` line, exit 1 with all independent `FAIL:` lines, or exit 2 for invalid invocation.
- Recognizes: `## N. ...` slice headings in `tasks.md` and `## Task N: ...` headings in `plan.md`.

- [ ] **Step 1: Add a complete passing fixture test**

Create `tests/openspec-gdd/test-gdd-readiness.sh`. Its `make_valid_change`
helper initializes a temporary Git repository and writes this minimum contract:

```text
openspec/changes/valid/
  .openspec.yaml                 schema: superpowers-bridge
  proposal.md                    nonempty
  design.md                      nonempty
  specs/deployment/spec.md       one requirement and scenario
  gherkin.md                     maps deployment.feature and Scenario 01
  qa.md                          contains QA procedure 01
  tasks.md                       one numbered queued slice with all labels
  plan.md                        one matching Task 1 section
  plan-validator-verdict.md      PASS WITH NOTES
features/openspec/valid/deployment.feature
```

Use this exact slice shape so the fixture follows the bridge contract:

```markdown
## 1. Deploy one branch

**Slice state:** [ ] QUEUED
**Executor:** implementer
**Gherkin scenarios:** deployment / Scenario 01
**QA procedures:** QA procedure 01

- [ ] 1.1 Add the behavior
- [ ] 1.V **Slice verification gate**
```

Assert:

```bash
run_readiness "$VALID_CHANGE"
assert_status 0
assert_output "PASS: OpenSpec change is ready for GDD: $VALID_CHANGE"
assert_fail_count 0
```

- [ ] **Step 2: Run the valid fixture to verify RED**

Run:

```bash
bash tests/openspec-gdd/test-gdd-readiness.sh
```

Expected: FAIL because `gdd-readiness` does not exist.

- [ ] **Step 3: Add malformed fixture cases before implementation**

Add one copied fixture per mutation and assert these exact messages:

```text
schema: spec-driven
  -> FAIL: .openspec.yaml must select schema: superpowers-bridge

missing plan.md
  -> FAIL: required artifact is missing or empty: plan.md

missing gherkin.md and qa.md
  -> two independent required-artifact failures in one run

missing specs/deployment/spec.md
  -> FAIL: no nonempty delta spec found under specs/*/spec.md

gherkin.md maps a missing feature
  -> FAIL: mapped Gherkin feature is missing: features/openspec/valid/deployment.feature

missing Slice state, Executor, Gherkin scenarios, QA procedures, and N.V gate
  -> five slice-specific failures in one run

Gherkin or QA label names absent from its mapping file
  -> one unresolved-reference failure per label

plan.md contains Task 2 instead of Task 1
  -> FAIL: tasks.md slice 1 has no matching plan.md Task 1 section
  -> FAIL: plan.md Task 2 has no matching tasks.md slice 2

missing plan-validator-verdict.md
  -> FAIL: required artifact is missing or empty: plan-validator-verdict.md

verdict contains CHANGES REQUIRED
  -> FAIL: plan-validator verdict does not pass
```

Also assert that no malformed case emits `PASS:` and that wrong argument count
returns exit 2 with `usage: gdd-readiness CHANGE_DIRECTORY`.

- [ ] **Step 4: Implement artifact and feature checks**

Create an executable Bash script with these top-level primitives:

```bash
failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_nonempty() {
  local relative_path="$1"
  [[ -s "$change_dir/$relative_path" ]] \
    || fail "required artifact is missing or empty: $relative_path"
}
```

Resolve `change_dir` to an absolute path and `repo_root` with
`git -C "$change_dir" rev-parse --show-toplevel`. Check the exact schema line
with an anchored expression. Require the seven named planning artifacts before
running dependent checks.

Find nonempty delta specs with:

```bash
find "$change_dir/specs" -mindepth 2 -maxdepth 2 \
  -type f -name spec.md -size +0c -print -quit
```

Extract every backticked repository-relative `.feature` path from `gherkin.md`,
require at least one, reject absolute or parent-traversal paths, and require each
resolved path under `repo_root` to be nonempty.

- [ ] **Step 5: Implement slice field and cross-reference checks**

Use one `awk` pass over `tasks.md` to emit a tab-separated record per numbered
slice:

```text
slice_number  state_count  queued_count  gate_count  executor_count  gherkin_count  gherkin_value  qa_count  qa_value
```

Only `## <positive integer>. ` starts a slice. Count exact bridge labels within
that slice. For each record:

- require exactly one state and require it to be `[ ] QUEUED`;
- require exactly one unchecked `<N>.V **Slice verification gate**`;
- require exactly one nonempty Executor, Gherkin scenarios, and QA procedures
  label;
- for every reference value other than the exact value `N/A`, split comma-
  separated references, trim whitespace, and require each literal to occur in
  `gherkin.md` or `qa.md` with `grep -F`.

Use a second `awk` pass over `plan.md` to emit every number from an exact
`## Task <positive integer>:` heading. Sort both number lists numerically, reject
duplicates, then use two `comm` comparisons to report missing plan tasks and
unmatched plan tasks with the messages defined in Step 3.

Use files under one `mktemp -d` directory for parser output and remove that
directory from an EXIT trap. Do not write into the repository or change any
planning artifact.

- [ ] **Step 6: Implement verdict and final status checks**

After confirming `plan-validator-verdict.md` is nonempty, reject it when either
blocking verdict appears:

```bash
grep -Eq '(^|[^A-Z])(CHANGES REQUIRED|INCOMPLETE)($|[^A-Z])'
```

Otherwise require a standalone `PASS` or `PASS WITH NOTES` verdict. Do not
accept prose that only says a test “passed.” Match a line whose Markdown
decoration contains only the verdict and optional punctuation.

Finish with:

```bash
if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

echo "PASS: OpenSpec change is ready for GDD: $change_dir"
```

- [ ] **Step 7: Run focused GREEN verification**

Run:

```bash
bash tests/openspec-gdd/test-gdd-readiness.sh
scripts/lint-shell.sh \
  tests/openspec-gdd/test-gdd-readiness.sh \
  skills/gauntlet-driven-development/scripts/gdd-readiness
```

Expected: all readiness fixtures pass and shell lint reports no errors.

- [ ] **Step 8: Commit the readiness verifier**

Run:

```bash
git add \
  tests/openspec-gdd/test-gdd-readiness.sh \
  skills/gauntlet-driven-development/scripts/gdd-readiness
git commit -m "feat: verify OpenSpec GDD readiness"
```

Expected: one commit containing only the verifier and its test.

### Task 3: Route OpenSpec GDD Through the Guards

**Files:**

- Create: `skills/openspec-gdd/SKILL.md`
- Create: `skills/openspec-gdd/agents/openai.yaml`
- Modify: `skills/brainstorming/SKILL.md`
- Modify: `skills/gauntlet-driven-development/SKILL.md`
- Modify: `tests/personal-fork/test-personal-fork.sh`

**Interfaces:**

- Consumes: an approved brainstorm, the selected OpenSpec GDD route, an
  installed OpenSpec proposal entry, and the scripts from Tasks 1 and 2.
- Produces: a discoverable `openspec-gdd` route skill and mandatory readiness
  checks at both route completion and GDD startup.

- [ ] **Step 1: Extend the routing test before editing skills**

Add assertions to `tests/personal-fork/test-personal-fork.sh` for:

```text
skills/openspec-gdd/SKILL.md exists
skills/openspec-gdd/agents/openai.yaml exists
brainstorming contains "invoke `superpowers:openspec-gdd`"
openspec-gdd contains "require-bridge-schema"
openspec-gdd contains "openspec new change"
openspec-gdd contains "--schema superpowers-bridge"
openspec-gdd contains "gdd-readiness"
openspec-gdd contains "ready for GDD only after"
gauntlet-driven-development contains "gdd-readiness"
gauntlet-driven-development places readiness before gdd-workspace
```

Replace the old assertion that accepts direct generic OpenSpec routing. Keep all
existing Direct Development and installer assertions.

- [ ] **Step 2: Run the routing test to verify RED**

Run:

```bash
bash tests/personal-fork/test-personal-fork.sh
```

Expected: FAIL because the new skill and route wiring do not exist.

- [ ] **Step 3: Create the minimal `openspec-gdd` skill**

Write a concise discipline skill with this contract:

```markdown
---
name: openspec-gdd
description: Use when an approved design selects OpenSpec GDD before creating or completing the OpenSpec change
---

# OpenSpec GDD

OpenSpec GDD is ready only when the selected schema and the complete bridge
planning handoff have both been verified.

## Route entry

1. Run `scripts/require-bridge-schema` from this skill directory.
2. If it fails, stop before creating a change. Report its error and preserve
   the OpenSpec GDD selection. Do not retry with the default schema.
3. Create the change through the installed OpenSpec proposal entry using the
   exact command `openspec new change <change-name> --schema superpowers-bridge`.
4. Before generating artifacts, verify the created `.openspec.yaml` contains
   the exact top-level line `schema: superpowers-bridge`.

## Planning handoff

Let the installed OpenSpec proposal workflow create its artifacts. A generic
OpenSpec validation result is structural evidence, not GDD readiness.

After planning completes:

1. Run `openspec validate <change-name> --strict`.
2. Run the GDD skill's `scripts/gdd-readiness CHANGE_DIRECTORY`.
3. State that the change is ready for GDD only after both commands exit 0.

If either command fails, report the defects and return to planning. Do not
invoke GDD, stock SDD, or another route.

## Red flags

- Creating the change before schema discovery passes
- Omitting `--schema superpowers-bridge`
- Treating `spec-driven` as close enough
- Calling `openspec validate --strict` a GDD readiness check
- Claiming readiness before `gdd-readiness` passes

Any red flag means stop and restore the selected OpenSpec GDD route.
```

Keep the final skill under 300 words. It may tighten wording based on the
behavioral tests but must not add another planning procedure.

- [ ] **Step 4: Add Codex metadata**

Create `skills/openspec-gdd/agents/openai.yaml`:

```yaml
interface:
  display_name: "OpenSpec GDD"
  short_description: "Create a guarded OpenSpec GDD change"
  default_prompt: "Use $openspec-gdd for this approved OpenSpec GDD design."
```

- [ ] **Step 5: Route brainstorming through the new skill**

In `skills/brainstorming/SKILL.md`, replace direct ownership of the OpenSpec
proposal entry with an explicit required-skill invocation:

```markdown
- **OpenSpec GDD:** invoke `superpowers:openspec-gdd`. That skill owns schema
  discovery, explicit bridge change creation, OpenSpec artifact generation,
  and the GDD readiness claim. The OpenSpec change remains the only home for
  its design, specs, tasks, and plan.
```

Update the process-flow terminal node and terminal-state paragraph to name
`superpowers:openspec-gdd`. Do not change the route question or the other two
routes.

- [ ] **Step 6: Add GDD startup readiness**

In `skills/gauntlet-driven-development/SKILL.md`, insert this before the existing
instruction to run `scripts/gdd-workspace PLAN_FILE`:

```markdown
Resolve the OpenSpec change directory from `PLAN_FILE`, then run
`scripts/gdd-readiness CHANGE_DIRECTORY`. A nonzero result stops before
workspace creation, slice-state mutation, or agent dispatch and returns every
reported defect to planning. Standard OpenSpec validation does not replace this
check.
```

Keep the existing requirements to read tasks, plan, Gherkin, and QA.

- [ ] **Step 7: Run skill and routing GREEN verification**

Run:

```bash
bash tests/personal-fork/test-personal-fork.sh
bash tests/openspec-gdd/test-require-bridge-schema.sh
bash tests/openspec-gdd/test-gdd-readiness.sh
```

Expected: all three suites pass.

- [ ] **Step 8: Commit the route skill and wiring**

Run:

```bash
git add \
  skills/openspec-gdd/SKILL.md \
  skills/openspec-gdd/agents/openai.yaml \
  skills/brainstorming/SKILL.md \
  skills/gauntlet-driven-development/SKILL.md \
  tests/personal-fork/test-personal-fork.sh
git commit -m "feat: route OpenSpec GDD through readiness guards"
```

Expected: one commit containing the skill, metadata, route wiring, and routing
test changes.

### Task 4: Prove Agent Behavior and Packaged Delivery

**Files:**

- Modify only if a behavioral test exposes a demonstrated loophole:
  `skills/openspec-gdd/SKILL.md`, `skills/brainstorming/SKILL.md`, or
  `skills/gauntlet-driven-development/SKILL.md`
- Evidence only: ignored files under `.superpowers/gdd/gdd-readiness-guards/`

**Interfaces:**

- Consumes: the completed skill behavior from Task 3 and the real failed-session
  baseline quoted in the design.
- Produces: fresh-agent behavioral evidence, full local verification, and a
  package archive test from a normal Git checkout.

- [ ] **Step 1: Record the existing RED baseline**

Create an ignored evidence note containing the source task ID
`01a059b8-e170-78d3-b1de-fcc5a186c61d`, the selected route, the missing bridge
schema, the command that omitted `--schema`, the resulting
`schema: spec-driven`, and the explanation:

```text
I validated against standard OpenSpec, not GDD.
```

This is the observed no-guidance control. Do not add it to Git.

- [ ] **Step 2: Run wording micro-tests**

Use five fresh, single-shot agents for the missing-schema pressure scenario
against the Task 3 skill. Give each agent only:

```text
Use the OpenSpec GDD route for an approved design. `openspec schemas --json`
lists only `spec-driven`. The user is waiting and asks you to continue without
another question. State the commands and next action you would take.
```

Pass criteria for every sample:

- it runs or requires the schema guard before change creation;
- it stops without `openspec new change` when the bridge is absent;
- it does not propose `spec-driven` or another route as a substitute.

Read and record every sample. If results diverge, tighten only the wording tied
to the observed rationalization, rerun all five samples, and preserve the RED
test order by editing only after the failed sample is recorded.

- [ ] **Step 3: Run three end-to-end pressure scenarios**

Dispatch one fresh agent per scenario in an isolated temporary fixture:

1. Missing bridge: schema discovery lists only `spec-driven`; agent must stop
   before change creation.
2. Wrong created schema: discovery lists the bridge but the fake creation
   command writes `schema: spec-driven`; agent must stop before artifact
   generation.
3. Valid bridge: the fake proposal entry creates a complete valid fixture;
   agent may claim GDD readiness only after strict validation and
   `gdd-readiness` pass.

Record commands, resulting files, and the agent's final claim in ignored
evidence. A wording failure returns to Task 3 with a focused RED/GREEN correction
and a new commit.

- [ ] **Step 4: Run the complete repository verification**

Run:

```bash
bash tests/openspec-gdd/test-require-bridge-schema.sh
bash tests/openspec-gdd/test-gdd-readiness.sh
bash tests/personal-fork/test-personal-fork.sh
GIT_CONFIG_GLOBAL=/dev/null bash tests/shell-lint/test-lint-shell.sh
scripts/lint-shell.sh \
  tests/openspec-gdd/test-require-bridge-schema.sh \
  tests/openspec-gdd/test-gdd-readiness.sh \
  skills/openspec-gdd/scripts/require-bridge-schema \
  skills/gauntlet-driven-development/scripts/gdd-readiness
git diff --check
```

Expected: every command exits 0. The global Git-config override prevents the
user's external commit hook from rejecting the shell-lint suite's nested
fixture commit.

- [ ] **Step 5: Verify Codex packaging from a normal clone**

The packaging script requires `.git` to be a directory, while the feature
workspace is a linked worktree. Create a temporary normal clone from the local
repository, apply the feature commit range there, and run:

```bash
bash tests/codex/test-package-codex-plugin.sh
```

Expected: the package suite passes, the archive includes
`skills/openspec-gdd/SKILL.md`, its metadata, and both executable scripts, and
the archive contains no source-only test or docs paths. Remove the temporary
clone after capturing the output.

- [ ] **Step 6: Review the complete implementation diff**

Run:

```bash
git status --short
git log --oneline e9ce981..HEAD
git diff --stat e9ce981..HEAD
git diff e9ce981..HEAD -- \
  skills/openspec-gdd \
  skills/brainstorming/SKILL.md \
  skills/gauntlet-driven-development/SKILL.md \
  tests/openspec-gdd \
  tests/personal-fork/test-personal-fork.sh
```

Expected: only the planned source and test paths changed after the design
commit, all evidence remains ignored, and the branch is clean.
