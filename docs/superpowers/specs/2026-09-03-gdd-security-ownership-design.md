# GDD Security Ownership Design

**Date:** 2026-09-03
**Status:** Draft for review

## Context

Gauntlet-Driven Development (GDD) runs each slice through `cleaner ->
architect -> security-reviewer -> hardener -> e2e-runner` and closes the
feature with one whole-branch Branch Reviewer. The orchestration text lives
in `skills/gauntlet-driven-development/SKILL.md` and the agent bodies in
`~/.claude/agents/`. This design removes the
per-slice Security stage, removes security review from the Branch Reviewer,
and adds one dedicated whole-branch Security Reviewer that reviews the same
diff as the Branch Reviewer, independently and in tandem.

## Goals

- Each slice runs `cleaner -> architect -> hardener -> e2e-runner`. No slice
  obligation, state, replay role, or finding origin refers to security.
- At feature closing the Branch Reviewer and the Security Reviewer each
  review the whole branch diff. Neither sees the other's verdict. The
  controller dispatches them in parallel.
- The Branch Reviewer owns coverage, scope, cross-slice integration, and
  quality. The Security Reviewer owns security. Neither reports on the
  other's concern.
- Findings from both reviewers join the one final fix wave. After replay, one
  fresh Branch Reviewer and one fresh Security Reviewer run. There is no
  second final fix wave.
- The same agent bodies drive both reviews in Claude Code and in Codex.

## Non-goals

- No deterministic security tooling in the ceremony. The Security Reviewer
  body keeps the analysis commands it already names.
- No new agent file. The installed `security-reviewer` agent is reworked for
  whole-branch dispatch.
- No readiness check for the `security-reviewer` agent files. No other GDD
  role has one.
- No ordering between the two feature reviews in the reducer.
- No migration for workspaces initialized at format version 1.

## Decisions

### D1: Remove the per-slice Security stage

The slice ceremony becomes `cleaner -> architect -> hardener -> e2e-runner`.
The `slice-N-security` obligation, the `verifying-security` slice state, the
`Security Reviewer` entry in every replay role list, and the `Security
Reviewer` origin for slice-scoped findings are deleted. `slice-N-hardener`
depends on `slice-N-architect`. `verifying-hardener` takes the Architect
report as its prior evidence.

The replay table becomes:

| Repair originated from | Delta-scoped replay roles              | Next normal full-slice pass |
| ---------------------- | -------------------------------------- | --------------------------- |
| Cleaner                | Cleaner                                | Architect                   |
| Architect              | Cleaner, Architect                     | Hardener                    |
| Hardener               | Cleaner, Architect, Hardener           | QA                          |
| QA                     | Cleaner, Architect, Hardener           | Fresh QA                    |

The two rationalization rows that mention "Fresh Security" and "through
Security" are deleted from `skills/gauntlet-driven-development/SKILL.md`.

### D2: Add a feature-level Security Review obligation

`compile_obligations` emits `feature-security-review` after
`feature-branch-review`:

| Field           | Value                                  |
| --------------- | -------------------------------------- |
| Depends on      | every `slice-N-verified`               |
| Allowed results | `PASS,FAIL`                            |
| Evidence kind   | `security-review-report`               |
| Finding origin  | `Security Reviewer`                    |
| Finding scope   | `feature`                              |

Both feature reviews depend only on the verified slices, so both are ready at
the same time. The controller must dispatch them in parallel, in one
dispatch turn, before accepting either report.
`feature-findings-digest` depends on both `feature-branch-review` and
`feature-security-review`. The result semantics mirror `feature-branch-review`:
an ACCEPT with `result-kind FAIL` does not complete the obligation, and the
digest cannot become ready until both reviews are accepted with PASS. The
`final_wave_pending` case that holds `feature-branch-review` at `PENDING`
holds `feature-security-review` the same way.

The report contract follows the role addendum. The Security Reviewer writes
its verdict with `Status: CLEAN` or `Status: FINDINGS`, exactly one
`Finding count: N` line, and one numbered finding file per finding in the
dispatched `FINDINGS_DIR` with `Origin role: Security Reviewer`. The
controller accepts the report with result `PASS` for `CLEAN` and `FAIL` for
`FINDINGS`. Acceptance validates the count against the files and the origin
against the obligation, the same checks `feature-branch-review` runs. The
verdict vocabulary in the agent body does not change.

### D3: Independent dispatch

The Security Reviewer's dispatch carries the same inputs as the Branch
Reviewer's dispatch: plan base ref and worktree path, spec sources, diff
package path or the instruction to generate it, the check command, every
unchanged finding with its ruling, and a unique verdict-file path. It does not
receive the Branch Reviewer verdict, and the Branch Reviewer does not receive
its verdict. Missing inputs return `Status: NEEDS_CONTEXT` naming them.

### D4: One final wave for both reviewers

New findings from either reviewer are recorded with scope `feature`. The
controller adjudicates both reports together. A finding both reviewers report
is recorded once, under the origin whose concern it is. The controller
registers all repairable findings into one `Final wave findings:` list,
issues one combined fixer dispatch, replays every affected slice through
Cleaner, Architect, Hardener, QA, and its final suite, and records
repair-finish and `RESOLVED` per finding.

The repair-acceptance branch that invalidates `feature-branch-review` also
invalidates `feature-security-review`. After the wave, the controller runs one
fresh Branch Reviewer and one fresh Security Reviewer, again independently.
Residual findings from either are adjudicated without a second final fix wave.

### D5: Finding rules for the Security Reviewer origin

In `gdd-finding-state`:

- `Security Reviewer` is a valid origin only with scope `feature`, the same
  rule that applies to `Branch Reviewer`. The two messages that say "feature
  findings must originate from Branch Reviewer" and "feature repair must
  originate from Branch Reviewer" accept either origin.
- `Security Reviewer` leaves the `Replay through` origin set and the slice
  stage rank table. Only Cleaner, Architect, Hardener, and QA remain.
- The obligation map returns `feature-security-review` for the `Security
  Reviewer` origin.

`finding_origin_for_obligation` in `gdd-workflow-state` maps
`feature-security-review` to `Security Reviewer` and drops the
`slice-*-security` case.

### D6: Rework the installed Security Reviewer for whole-branch dispatch

`~/.claude/agents/security-reviewer.md` keeps its frontmatter name and tool
list. Its description, Dispatch section, and routing sentence change:

- Description: read-only whole-branch security reviewer dispatched once after
  every slice is verified, and once more after the final wave.
- Dispatch inputs: the D3 list.
- The review method (authz obligations first, per-handler AUTHZ CHECK, lens
  scan, test discrimination, backward trace) is unchanged. It runs over the
  whole branch diff instead of one slice diff.
- The sentence "Only `Status: CLEAN` hands the slice to the Hardener. Findings
  route to a fixer, then scoped Cleaner and Architect reruns, followed by a
  fresh Security Reviewer." is replaced with: findings are recorded with scope
  `feature` and join the final wave. A fresh Security Reviewer runs after
  replay.
- Model pin moves from opus to fable at high effort, with the same
  cross-model rationale the Branch Reviewer states: the top review rung
  reviews opus-tier implement and fix work. The hook case for
  `security-reviewer` in `guard-dispatch-model.sh` changes from `*opus*` to
  `*fable*`.

`codex-agents/security-reviewer.toml` is regenerated from the new body: new
description, `model_reasoning_effort = "xhigh"` to match the Branch Reviewer
TOML, the same `gpt-5.6-sol` model, the new body SHA-256, and the byte-for-byte
body after the `SOURCE_BODY_BEGIN` marker. The Codex adaptation section drops
"Review only the dispatched slice" for "Review only the dispatched branch
diff".

### D7: Remove security from the Branch Reviewer

`~/.claude/agents/branch-reviewer.md` loses every security responsibility:

- The description drops "and emergent security risks".
- The opening paragraph drops "and security risks created by the slices in
  combination".
- Method step 7, "Emergent security pass", is deleted. The remaining steps
  keep their order.
- A sentence under Method states that security review belongs to the Security
  Reviewer and that the Branch Reviewer does not report or suggest security
  findings.

`codex-agents/branch-reviewer.toml` is regenerated from the new body with the
new description and body SHA-256.

Two other role bodies name the per-slice handoff. `agents/architect.md` says
three times that its handoff goes to the Security Reviewer. Each becomes the
Hardener. `agents/e2e-runner.md` describes the post-repair replay as "fresh
Security Reviewer, Hardener, and QA passes". The Security Reviewer is removed
from that sentence. Both Codex TOMLs are regenerated with new body SHA-256
values. The parity test `superpowers-bridge/scripts/agent-source-parity.test.sh`
asserts the Architect handoff sentence names the Security Reviewer and that
the Codex Security Reviewer runs at high reasoning. Both assertions change to
the Hardener and xhigh.

The feature-closing paragraph in
`skills/gauntlet-driven-development/SKILL.md`, which tells the controller
what to dispatch the Branch Reviewer for, drops "and emergent cross-slice
security".

### D8: Bump the workflow format version to 2

Dropping `slice-N-security` from the obligation-ID regex makes every existing
`obligations.tsv` invalid. `gdd-workflow-state` writes `2` to
`format-version` at initialization and rejects any other value.
`gdd-readiness` expects `2`. The `workflow-v1` directory name does not change.
A workspace initialized at format 1 fails with "workflow format version is
unknown: 1" and is not migrated.

### D9: Policy version 2

`finding-policy.md` Feature closing changes from "run one fresh whole-branch
Branch Reviewer" to "run one fresh whole-branch Branch Reviewer and one fresh
whole-branch Security Reviewer", and its first sentence names both reviewers
as recipients of every `DEFERRED`, `DISMISSED`, and `PARKED` finding. The
Role gates sentence "Adjudication may route a Security or Branch Review
finding" is unchanged. `Policy-Version` becomes 2 and
`EXPECTED_POLICY_VERSION` in `gdd-readiness` matches.

## Components and data flow

1. Slices run `implementer -> cleaner -> architect -> hardener -> e2e-runner`.
   `gdd-slice-state` advances `implementing -> verifying-cleaner ->
   verifying-architect -> verifying-hardener -> verifying-qa -> verified`.
2. When every `slice-N-verified` is complete, `feature-branch-review` and
   `feature-security-review` are both ready. The controller dispatches the
   Branch Reviewer and the Security Reviewer in parallel with the same branch
   package and accepts each report with PASS or FAIL.
3. The controller records new findings from both reports with scope `feature`,
   adjudicates them together, and moves repairable ones to `REPAIRING` with
   one `Final wave findings:` list.
4. One combined fixer dispatch, affected-slice replay, repair-finish, and
   `RESOLVED` follow the final-wave dispatch order. Repair acceptance
   invalidates both review obligations.
5. One fresh Branch Reviewer and one fresh Security Reviewer. Residual
   findings are adjudicated without a second wave.
6. `feature-findings-digest` becomes ready when both reviews hold a PASS
   acceptance, then `feature-complete`.

## File map

claude-config repository:

- `agents/security-reviewer.md`: D6.
- `agents/branch-reviewer.md`, `agents/architect.md`, `agents/e2e-runner.md`:
  D7.
- `codex-agents/security-reviewer.toml`, `codex-agents/branch-reviewer.toml`,
  `codex-agents/architect.toml`, `codex-agents/e2e-runner.toml`: regenerated
  from the new bodies.
- `superpowers-bridge/scripts/agent-source-parity.test.sh`: D7 assertions.
- `hooks/guard-dispatch-model.sh`: `security-reviewer` case pins fable.

superpowers repository, `skills/gauntlet-driven-development/`:

- `SKILL.md`: ceremony line, replay table, final-wave dispatch order,
  feature-closing paragraphs, two rationalization rows. The addendum role
  list is unchanged because the Security Reviewer still receives it.
- `finding-policy.md`: D9.
- `scripts/gdd-workflow-state`: `compile_obligations`, obligation-ID regex,
  replay role lists, projected-state cases, the `final_wave_pending` case,
  the invalidation branch, and `finding_origin_for_obligation`. Format
  version 2.
- `scripts/gdd-slice-state`: remove `verifying-security` and the
  `slice-N-security` accept-active case.
- `scripts/gdd-finding-state`: D5.
- `scripts/gdd-readiness`: `EXPECTED_POLICY_VERSION='Policy-Version: 2'` and
  format version 2.
- `scripts/gdd-workflow-state.test.sh`, `scripts/gdd-slice-state.test.sh`,
  `scripts/gdd-finding-state.test.sh`: replace every `slice-1-security` and
  `verifying-security` fixture, add `feature-security-review` cases. The
  workflow-state test asserts format version `1` on initialization and treats
  `2` as unknown. Both assertions flip.
- `tests/openspec-gdd/test-gdd-readiness.sh`: the policy fixture and the
  expected failure message name `Policy-Version: 1`, and one case expects
  format version `2` to be rejected. All three flip.

## Error handling

- Either reviewer returns `NEEDS_CONTEXT` when the base ref or spec sources
  are missing. The controller supplies the input and redispatches.
- A slice-scoped finding with origin `Security Reviewer` fails validation.
- A format-1 workspace fails reduction with the unknown-version message.

## Risks

- Security findings surface after every slice has passed Hardener and QA, so
  a security repair replays more slices than a per-slice finding would have.
- Both reviewers may report the same defect. Adjudication records it once.
- Each reviewer reads the whole branch diff in one context. A long branch may
  exceed what one review can hold.

## Verification

- Script tests pass with the new fixtures: no `slice-N-security`, both
  feature reviews ready together once every slice is verified, a digest that
  stays `PENDING` until both reviews hold PASS, and invalidation of both on
  repair acceptance.
- `gdd-finding-state` rejects a slice-scoped `Security Reviewer` finding and
  accepts a feature-scoped one.
- `gdd-readiness` fails on `Policy-Version: 1` and on format version 1.
- `scripts/install-codex-agents.test.sh` and
  `superpowers-bridge/scripts/agent-source-parity.test.sh` pass with the four
  regenerated TOMLs.
- The hook denies an opus override for `security-reviewer` and allows fable.
- One manual run of the feature closing in Claude Code and one in Codex, each
  producing a Branch Reviewer report with no security findings and a Security
  Reviewer report.
