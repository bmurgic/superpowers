# OpenSpec GDD Route and Readiness Guards Design

**Date:** 2026-08-31
**Status:** Approved

## Context

The brainstorming route currently tells an agent to enter OpenSpec with the
`superpowers-bridge` schema, but it does not provide an executable route guard.
An agent can therefore create a change with OpenSpec's default `spec-driven`
schema, run `openspec validate --strict`, and incorrectly report that the plan
is ready for Gauntlet-Driven Development (GDD).

That failure occurred in a real planning session. The selected route was
OpenSpec GDD, but the repository did not have `superpowers-bridge` installed.
The agent created a default `spec-driven` change and later explained, “I
validated against standard OpenSpec, not GDD.” GDD correctly refused to start
because the change lacked the bridge-owned plan, Gherkin, QA, slice-state, and
verification-gate artifacts.

The existing bridge already defines the required planning lifecycle. The gap is
enforcement at route entry and handoff, not a new planning format.

## Goals

- Stop before change creation when `superpowers-bridge` is unavailable.
- Create OpenSpec GDD changes with an explicit schema and verify the recorded
  schema immediately.
- Use one deterministic readiness contract before reporting a plan as GDD-ready
  and again before GDD starts.
- Report every readiness defect in one run with stable, actionable messages.
- Prove the behavioral correction against the observed failure, not only with
  static text assertions.

## Non-Goals

- Do not change the `superpowers-bridge` schema or OpenSpec itself.
- Do not make ordinary `spec-driven` changes invalid or GDD-compatible.
- Do not make GDD fall back to stock Subagent-Driven Development.
- Do not add a Markdown or YAML dependency.
- Do not redesign GDD slice execution, plan validation, or plugin installation.
- Do not add the external `superpowers-evals` repository to this checkout.

## Decisions

### D1. Give the OpenSpec GDD route one owner

Add an `openspec-gdd` skill and route brainstorming's OpenSpec GDD selection to
it. The skill owns the transition from an approved brainstorm to the installed
OpenSpec proposal workflow. It invokes change creation with
`--schema superpowers-bridge`, verifies the resulting change metadata, and owns
the final readiness statement.

This is preferable to adding more prose to brainstorming. Brainstorming remains
the route selector, while the new skill contains the OpenSpec-specific entry
contract and can be tested independently.

The skill wraps the installed OpenSpec proposal entry rather than copying its
artifact-generation procedure. After that procedure returns, `openspec-gdd`
runs the readiness verifier. A generic OpenSpec completion message is not a GDD
readiness decision.

### D2. Fail closed before creating a change

Add `skills/openspec-gdd/scripts/require-bridge-schema`. It runs
`openspec schemas --json` and succeeds only when the output names
`superpowers-bridge`. The script emits a single actionable error and exits
nonzero when OpenSpec is missing, schema discovery fails, or the bridge is not
installed.

The skill runs this guard before `openspec new change`. It must not retry without
the schema, substitute `spec-driven`, or create a partial change directory.

Immediately after creation, the skill verifies that the change's
`.openspec.yaml` contains the exact top-level record
`schema: superpowers-bridge`. A missing or different value stops the route
before artifact generation.

### D3. Share one readiness verifier

Add `skills/gauntlet-driven-development/scripts/gdd-readiness`. Both
`openspec-gdd` and `gauntlet-driven-development` call this script with the
change directory:

```text
gdd-readiness CHANGE_DIRECTORY
```

The script is read-only. It prints one `FAIL:` line for every defect, exits 1
when any check fails, and prints one `PASS:` line and exits 0 only when the
complete contract passes. Invalid invocation exits 2.

Keeping the verifier under GDD makes the execution controller authoritative for
its input contract. The route-entry skill depends on that contract instead of
maintaining a second interpretation.

### D4. Check the stable bridge contract, not arbitrary Markdown style

The verifier checks these bridge-owned invariants:

1. `.openspec.yaml` selects `superpowers-bridge`.
2. `proposal.md`, `design.md`, `gherkin.md`, `qa.md`, `tasks.md`, and `plan.md`
   exist and are nonempty.
3. At least one delta spec exists at `specs/*/spec.md` and at least one generated
   feature exists at the repository-relative path recorded by `gherkin.md`.
4. Every numbered `## N.` task slice contains exactly one
   `**Slice state:** [ ] QUEUED` line, one unchecked
   `N.V **Slice verification gate**`, one `**Executor:**` line, one
   `**Gherkin scenarios:**` line, and one `**QA procedures:**` line.
5. Every non-`N/A` Gherkin and QA reference in a slice resolves to text in
   `gherkin.md` or `qa.md`, respectively.
6. `plan.md` contains exactly one `## Task N:` section for every task slice and
   no unmatched task number.
7. `plan-validator-verdict.md` exists, is nonempty, contains a passing verdict
   of `PASS` or `PASS WITH NOTES`, and contains no `CHANGES REQUIRED` or
   `INCOMPLETE` verdict.

The script parses only the headings and labeled fields prescribed by the bridge.
It does not attempt to understand general Markdown, judge requirement quality,
or duplicate `openspec validate --strict`.

A missing plan-validator verdict remains a blocking readiness result. The bridge
has a human-visible fallback when the agent role is unavailable, but that
fallback is not equivalent to a validated, GDD-ready plan and must not produce
the normal readiness claim.

### D5. Make readiness claims conditional on the verifier

`openspec-gdd` runs `openspec validate <change-name> --strict` for structural
validation and then `gdd-readiness`. It may state that the change is ready for
GDD only after both commands pass.

`gauntlet-driven-development` runs `gdd-readiness` before creating its workspace,
changing slice state, or dispatching an Implementer. A failure stops execution
and returns the verifier's defects to planning. This second call protects
against stale, altered, or manually created changes.

### D6. Test mechanics and agent behavior separately

Add focused shell tests for both scripts. Fixtures cover:

- bridge schema present and absent from schema discovery;
- a complete bridge change;
- a `spec-driven` change with otherwise plausible files;
- missing plan, Gherkin, QA, slice metadata, references, feature files, and
  plan-validator verdict;
- mismatched task and plan slice numbers; and
- a failing verdict.

Extend the personal-fork routing test to assert that brainstorming routes through
`openspec-gdd`, that the new skill invokes the explicit bridge schema, and that
both route completion and GDD startup name the shared verifier.

The observed failed transcript is the RED behavioral baseline required by
`superpowers:writing-skills`. After implementation, fresh-agent pressure tests
exercise the same choice under missing-schema and default-schema pressure, plus
a valid bridge case. The result passes only when agents stop without creating a
fallback change in the first two cases and claim readiness only after the
verifier passes in the third.

The repository has no local copy of `superpowers-evals`, so these pressure-test
results are recorded as implementation evidence rather than adding a new eval
framework or committing generated transcripts.

## Components and Data Flow

```text
approved brainstorm
        |
        v
brainstorming selects OpenSpec GDD
        |
        v
openspec-gdd -> require-bridge-schema
        |                 |
        |                 +-- fail: stop before change creation
        v
openspec new change --schema superpowers-bridge
        |
        v
OpenSpec proposal workflow creates and validates artifacts
        |
        v
gdd-readiness -> fail: return defects to planning
        |
        v
ready-for-GDD claim
        |
        v
gauntlet-driven-development -> gdd-readiness -> first slice
```

## File Map

- Create `skills/openspec-gdd/SKILL.md` for route entry and readiness ownership.
- Create `skills/openspec-gdd/agents/openai.yaml` for Codex skill metadata.
- Create `skills/openspec-gdd/scripts/require-bridge-schema` for deterministic
  schema discovery.
- Create `skills/gauntlet-driven-development/scripts/gdd-readiness` for the
  shared handoff contract.
- Modify `skills/brainstorming/SKILL.md` to route OpenSpec GDD through the new
  skill.
- Modify `skills/gauntlet-driven-development/SKILL.md` to run readiness before
  setup.
- Create focused script tests under `tests/openspec-gdd/`.
- Modify `tests/personal-fork/test-personal-fork.sh` for route integration.

## Error Handling

Every guard is fail-closed and read-only. Errors name the failed invariant and
the relevant path. The route skill preserves the user's selected route and tells
them to install the bridge or repair planning artifacts. It never changes the
route, deletes a change, or edits planning artifacts automatically.

The readiness verifier accumulates independent defects so one run is enough to
identify a malformed handoff. Checks that depend on a missing file are skipped
after reporting that file, preventing secondary noise.

## Risks and Mitigations

- **R1: Markdown parsing becomes brittle.** Limit parsing to exact bridge-owned
  headings and labels, and cover every accepted shape with fixtures.
- **R2: The route skill duplicates OpenSpec behavior.** Delegate artifact
  generation to the installed OpenSpec proposal entry and keep only entry and
  exit guards in the new skill.
- **R3: Agents ignore prose and call OpenSpec directly.** Put route selection in
  brainstorming, use an explicit command recipe, and run fresh-agent pressure
  tests against the observed failure.
- **R4: A plan changes after validation.** Run the same readiness verifier again
  at GDD startup. Existing plan-validator commit discipline remains responsible
  for review provenance.
- **R5: Linked worktrees break unrelated packaging tests.** Run focused tests in
  this worktree. Run the package test from a temporary normal clone because the
  current packager requires `.git` to be a directory.

## Verification

The completed change must pass:

```bash
bash tests/openspec-gdd/test-require-bridge-schema.sh
bash tests/openspec-gdd/test-gdd-readiness.sh
bash tests/personal-fork/test-personal-fork.sh
GIT_CONFIG_GLOBAL=/dev/null bash tests/shell-lint/test-lint-shell.sh
git diff --check
```

The package test must also pass from a temporary normal clone with the working
tree changes applied. The environment override on shell lint isolates the suite
from the user's global commit hook, which otherwise rejects the suite's nested
fixture commit before lint assertions run.

Fresh-agent behavioral evidence must show the missing-schema and wrong-schema
cases stop, while the valid bridge case reaches the verifier-backed readiness
claim.

