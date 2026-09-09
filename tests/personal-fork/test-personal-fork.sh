#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ROUTING_SKILL="$REPO_ROOT/skills/brainstorming/SKILL.md"
DIRECT_DEVELOPMENT_SKILL="$REPO_ROOT/skills/direct-development/SKILL.md"
OPENSPEC_GDD_SKILL="$REPO_ROOT/skills/openspec-gdd/SKILL.md"
OPENSPEC_GDD_METADATA="$REPO_ROOT/skills/openspec-gdd/agents/openai.yaml"
GDD_SKILL="$REPO_ROOT/skills/gauntlet-driven-development/SKILL.md"
GDD_WORKFLOW_STATE="$REPO_ROOT/skills/gauntlet-driven-development/scripts/gdd-workflow-state"
GDD_WORKFLOW_STATE_TEST="$REPO_ROOT/skills/gauntlet-driven-development/scripts/gdd-workflow-state.test.sh"
STOCK_SDD_SKILL="$REPO_ROOT/skills/subagent-driven-development/SKILL.md"
FINISHING_SKILL="$REPO_ROOT/skills/finishing-a-development-branch/SKILL.md"
DIRECT_DEVELOPMENT_METADATA="$REPO_ROOT/skills/direct-development/agents/openai.yaml"
MICRO_CHANGE_SKILL="$REPO_ROOT/skills/micro-change/SKILL.md"
MICRO_CHANGE_METADATA="$REPO_ROOT/skills/micro-change/agents/openai.yaml"
INSTALLER="$REPO_ROOT/scripts/install-personal-fork"
TEST_ROOT="$(mktemp -d /tmp/superpowers-personal-fork.XXXXXX)"

cleanup() {
  case "$TEST_ROOT" in
    /tmp/superpowers-personal-fork.*) rm -rf -- "$TEST_ROOT" ;;
    *) printf 'Refusing to remove unexpected test path: %s\n' "$TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT

rg -qF 'Which route do you want?' "$ROUTING_SKILL"
rg -qF 'Superpowers plan' "$ROUTING_SKILL"
rg -qF 'Direct Development' "$ROUTING_SKILL"
rg -qF 'superpowers:direct-development' "$ROUTING_SKILL"
rg -qF 'Micro Change' "$ROUTING_SKILL"
rg -qF 'superpowers:micro-change' "$ROUTING_SKILL"
rg -qF 'I suggest <route> because <one short reason>.' "$ROUTING_SKILL"
rg -qF 'explicitly invoked' "$ROUTING_SKILL"
rg -qF 'invoke `superpowers:openspec-gdd`' "$ROUTING_SKILL"

test -f "$OPENSPEC_GDD_SKILL"
test -f "$OPENSPEC_GDD_METADATA"
rg -qF "Run the installed \`openspec-gdd\` skill's absolute \`scripts/require-bridge-schema\` path from the active project root." "$OPENSPEC_GDD_SKILL"
if rg -qF 'from this skill directory' "$OPENSPEC_GDD_SKILL"; then
  printf 'FAIL  OpenSpec GDD schema guard changes out of the active project root\n' >&2
  exit 1
fi
rg -qF 'openspec-propose' "$OPENSPEC_GDD_SKILL"
rg -qF 'openspec new change' "$OPENSPEC_GDD_SKILL"
rg -qF -- '--schema superpowers-bridge' "$OPENSPEC_GDD_SKILL"
rg -qF 'gdd-readiness' "$OPENSPEC_GDD_SKILL"
rg -qF 'from the installed `gauntlet-driven-development` skill directory' "$OPENSPEC_GDD_SKILL"
rg -qF 'scripts/gdd-readiness CHANGE_DIRECTORY' "$OPENSPEC_GDD_SKILL"
rg -qF 'ready for GDD only after' "$OPENSPEC_GDD_SKILL"
rg -qF 'scripts/gdd-readiness CHANGE_DIRECTORY' "$GDD_SKILL"
rg -qF 'A nonzero result stops before workspace creation, slice-state mutation, or agent dispatch and returns every reported defect to planning.' "$GDD_SKILL"
rg -qF 'scripts/gdd-workflow-state PLAN_FILE init' "$GDD_SKILL"
rg -qF 'scripts/gdd-workflow-state PLAN_FILE next' "$GDD_SKILL"
rg -qF 'claim the returned obligation before dispatch' "$GDD_SKILL"
rg -qF 'accept only the receipt-bound result' "$GDD_SKILL"
rg -qF 'continue while a ready obligation exists' "$GDD_SKILL"
rg -qF 'USER_AUTHORITY_REQUIRED' "$GDD_SKILL"
rg -qF 'Completion evidence:' "$GDD_SKILL"
test -x "$GDD_WORKFLOW_STATE"
test -x "$GDD_WORKFLOW_STATE_TEST"

if rg -qF 'gdd-workflow-state' "$STOCK_SDD_SKILL"; then
  printf 'FAIL  stock SDD must not depend on the GDD workflow engine\n' >&2
  exit 1
fi

# GDD owns lifecycle-finding adjudication without routing an OpenSpec run
# through stock SDD. These literals are the controller contract consumed by
# the personal fork test rather than behavior duplicated in lifecycle roles.
rg -qF 'finding-policy.md' "$GDD_SKILL"
rg -qF 'gdd-finding-state PLAN_FILE init' "$GDD_SKILL"
rg -qF 'gdd-finding-state PLAN_FILE supplement' "$GDD_SKILL"
rg -qF 'gdd-finding-state PLAN_FILE repair-start' "$GDD_SKILL"
rg -qF 'gdd-finding-state PLAN_FILE repair-finish' "$GDD_SKILL"
rg -qF '[gdd-finding-report]' "$GDD_SKILL"
rg -qF 'technical claim' "$GDD_SKILL"
rg -qF 'Do not choose the workflow disposition' "$GDD_SKILL"
rg -qF 'REPORTED' "$GDD_SKILL"
rg -qF 'REPAIRING' "$GDD_SKILL"
rg -qF 'RESOLVED' "$GDD_SKILL"
rg -qF 'DEFERRED' "$GDD_SKILL"
rg -qF 'DISMISSED' "$GDD_SKILL"
rg -qF 'PARKED' "$GDD_SKILL"
rg -qF 'BLOCKED' "$GDD_SKILL"
rg -qF 'Finding ID' "$GDD_SKILL"
rg -qF 'Ruling' "$GDD_SKILL"
rg -qF 'Cost if wrong' "$GDD_SKILL"
rg -qF 'Wake condition' "$GDD_SKILL"
rg -qF 'full branch review package' "$GDD_SKILL"
rg -qF 'approved OpenSpec artifacts' "$GDD_SKILL"
rg -qF 'astra-advisor' "$GDD_SKILL"
rg -qF 'Round 1 uses `fixer`' "$GDD_SKILL"
rg -qF 'Rounds 2 through 5 use a fresh `fixer-max`' "$GDD_SKILL"
rg -qF 'one fix dispatch' "$GDD_SKILL"
rg -qF 'every affected slice' "$GDD_SKILL"
rg -qF 'repair-finish only after every affected slice reaches its replay endpoint' "$GDD_SKILL"
rg -qF 'one fresh whole-branch Branch Reviewer' "$GDD_SKILL"
rg -qF 'There is no second final fix wave' "$GDD_SKILL"
rg -qF 'Findings digest:' "$GDD_SKILL"
rg -qF 'Complete every finding scenario as an execution record, not a proposed workflow.' "$GDD_SKILL"
rg -qF 'Hardener mutation evidence remains mandatory;' "$GDD_SKILL"
rg -qF 'acceptance evidence remains mandatory.' "$GDD_SKILL"
rg -qF 'Astra unavailability blocks the finding on its gating boundary.' "$GDD_SKILL"
rg -qF "A woken finding's dependent dispatch must contain its Finding ID, Ruling," "$GDD_SKILL"
rg -qF 'Cost if wrong, and Wake condition.' "$GDD_SKILL"
rg -qF 'later resolves.' "$GDD_SKILL"
rg -qF 'A final-wave record places every affected-slice replay endpoint before' "$GDD_SKILL"
rg -qF '`repair-finish`, `RESOLVED`, and one fresh whole-branch Branch Reviewer, in' "$GDD_SKILL"
rg -qF "originating role's \`Technical verdict:\`, \`Severity claim:\`, and" "$GDD_SKILL"
rg -qF 'Do not end the controller turn at a Astra request' "$GDD_SKILL"
rg -qF 'records the `repair-finish` command before' "$GDD_SKILL"
rg -qF 'disposition records final-digest retention and the `digest` command' "$GDD_SKILL"
rg -qF 'A stopped or `BLOCKED` boundary does not waive' "$GDD_SKILL"
rg -qF 'When Astra is unavailable, `BLOCKED` is required.' "$GDD_SKILL"
rg -qF 'adjudicate every recorded finding under this policy' "$GDD_SKILL"
rg -qF '### Per-finding execution record' "$GDD_SKILL"
rg -qF 'Copy the first four values from the role report without paraphrasing.' "$GDD_SKILL"
rg -qF 'Originating role: <role>' "$GDD_SKILL"
rg -qF 'Technical verdict: <literal role verdict>' "$GDD_SKILL"
rg -qF 'Severity claim: <literal role severity>' "$GDD_SKILL"
rg -qF 'Blocking claim: <literal role blocking claim>' "$GDD_SKILL"
rg -qF 'Finding ID: <ID>' "$GDD_SKILL"
rg -qF 'Verified claim: <falsifiable claim and evidence result>' "$GDD_SKILL"
rg -qF 'Disposition: <state transition and outcome>' "$GDD_SKILL"
rg -qF 'Ruling: <controller ruling>' "$GDD_SKILL"
rg -qF 'Cost if wrong: <concrete consequence>' "$GDD_SKILL"
rg -qF 'Wake condition: <observable condition>' "$GDD_SKILL"
rg -qF 'Astra result: <actual advisory result>' "$GDD_SKILL"
rg -qF 'Astra gate: NOT REQUIRED: <evidence-backed checked conditions>' "$GDD_SKILL"
rg -qF 'Mandatory gates: Hardener mutation evidence remains mandatory; QA acceptance evidence remains mandatory.' "$GDD_SKILL"
rg -qF 'Digest retention: <retained unchanged or N/A because RESOLVED>' "$GDD_SKILL"
rg -qF 'Issued next dispatch: <actual issued lifecycle or dependent dispatch, or STOPPED: interruption condition>' "$GDD_SKILL"
rg -qF '`UNAVAILABLE` is valid only after an actual `astra-advisor` invocation fails.' "$GDD_SKILL"
rg -qF 'Prompt constraints, test fixtures, and lack of shell execution do not prove unavailability.' "$GDD_SKILL"
rg -qF 'issue the dependent dispatch in the same controller turn after `RESOLVED`' "$GDD_SKILL"
rg -qF 'The issued dispatch includes the Finding ID, prior Ruling, Cost if wrong, and Wake condition.' "$GDD_SKILL"
rg -qF 'Issued combined fixer dispatch:' "$GDD_SKILL"
rg -qF 'Final wave findings:' "$GDD_SKILL"
rg -qF 'immutable final-wave identity' "$GDD_SKILL"
rg -qF 'wave-wide affected-slice union' "$GDD_SKILL"
rg -qF 'Record that dispatch at its execution point before any replay command.' "$GDD_SKILL"
rg -qF '### Ordered slice-repair execution record' "$GDD_SKILL"
rg -qF 'Final-wave repairs use the stricter order below.' "$GDD_SKILL"

rg -qF 'Findings digest:' "$FINISHING_SKILL"
rg -qF 'These findings were left unchanged. Do you want action on any of them?' "$FINISHING_SKILL"
rg -qF '1. No, continue to the branch options.' "$FINISHING_SKILL"
rg -qF '2. Yes, create follow-up work for selected findings.' "$FINISHING_SKILL"
rg -qF '3. Ask Astra to reconsider selected findings.' "$FINISHING_SKILL"
rg -qF 'Implementation complete. What would you like to do?' "$FINISHING_SKILL"
rg -qF "Implementation complete. You're on a detached HEAD (externally managed workspace)." "$FINISHING_SKILL"

if rg -qF 'Invoke stock SDD as the controller.' "$GDD_SKILL"; then
  printf 'FAIL  GDD must not invoke stock SDD as its controller\n' >&2
  exit 1
fi
if rg -qiF 'invoke `superpowers:subagent-driven-development` as the controller' "$GDD_SKILL"; then
  printf 'FAIL  GDD must not invoke stock SDD as its controller\n' >&2
  exit 1
fi
if rg -qiF 'controller decides the next lifecycle step from its own reconstruction' "$GDD_SKILL"; then
  printf 'FAIL  GDD controller must use workflow state instead of reconstruction\n' >&2
  exit 1
fi
if rg -qiF 'every finding automatically routes to repair' "$GDD_SKILL"; then
  printf 'FAIL  GDD must adjudicate rather than automatically repair every finding\n' >&2
  exit 1
fi

python3 - "$GDD_SKILL" <<'PY'
import pathlib
import sys

gdd_skill = pathlib.Path(sys.argv[1]).read_text()
workspace = gdd_skill.index("scripts/gdd-workspace PLAN_FILE")
assert gdd_skill.index("scripts/gdd-readiness CHANGE_DIRECTORY") < workspace
assert gdd_skill.index("A nonzero result stops before workspace creation, slice-state mutation, or agent dispatch and returns every reported defect to planning.") < workspace

finding_record = gdd_skill.index("### Per-finding execution record")
origin = gdd_skill.index("Originating role: <role>", finding_record)
technical_verdict = gdd_skill.index("Technical verdict: <literal role verdict>", finding_record)
severity = gdd_skill.index("Severity claim: <literal role severity>", finding_record)
blocking = gdd_skill.index("Blocking claim: <literal role blocking claim>", finding_record)
finding_id = gdd_skill.index("Finding ID: <ID>", finding_record)
verified_claim = gdd_skill.index("Verified claim: <falsifiable claim and evidence result>", finding_record)
astra_result = gdd_skill.index("Astra result: <actual advisory result>", finding_record)
disposition = gdd_skill.index("Disposition: <state transition and outcome>", finding_record)
ruling = gdd_skill.index("Ruling: <controller ruling>", finding_record)
cost = gdd_skill.index("Cost if wrong: <concrete consequence>", finding_record)
wake = gdd_skill.index("Wake condition: <observable condition>", finding_record)
mandatory_gates = gdd_skill.index("Mandatory gates: Hardener mutation evidence remains mandatory; QA acceptance evidence remains mandatory.", finding_record)
digest = gdd_skill.index("Digest retention: <retained unchanged or N/A because RESOLVED>", finding_record)
next_dispatch = gdd_skill.index("Issued next dispatch: <actual issued lifecycle or dependent dispatch, or STOPPED: interruption condition>", finding_record)
assert origin < technical_verdict < severity < blocking < finding_id < verified_claim < astra_result < disposition < ruling < cost < wake < mandatory_gates < digest < next_dispatch

repair_record = gdd_skill.index("### Ordered slice-repair execution record")
repair_start = gdd_skill.index("1. `repair-start`", repair_record)
fixer_dispatch = gdd_skill.index("2. `Issued fixer dispatch:`", repair_record)
replay_endpoint = gdd_skill.index("3. `Originating replay endpoint:`", repair_record)
repair_finish = gdd_skill.index("4. `repair-finish`", repair_record)
resolved = gdd_skill.index("5. `RESOLVED`", repair_record)
remaining_gates = gdd_skill.index("6. `Remaining first-pass lifecycle gates:`", repair_record)
final_suite = gdd_skill.index("7. `Passing final-suite evidence:`", repair_record)
assert repair_start < fixer_dispatch < replay_endpoint < repair_finish < resolved < remaining_gates < final_suite

final_wave = gdd_skill.index("### Final-wave dispatch order")
combined_dispatch = gdd_skill.index("1. `Issued combined fixer dispatch:`", final_wave)
affected_replay = gdd_skill.index("2. `Affected-slice replay:`", final_wave)
final_wave_suite = gdd_skill.index("3. `Passing final-suite evidence:`", final_wave)
final_wave_finish = gdd_skill.index("4. `repair-finish`", final_wave)
final_wave_resolved = gdd_skill.index("5. `RESOLVED`", final_wave)
branch_review = gdd_skill.index("6. `Fresh whole-branch Branch Reviewer:`", final_wave)
assert combined_dispatch < affected_replay < final_wave_suite < final_wave_finish < final_wave_resolved < branch_review
PY
if rg -qiF 'direct PR' "$ROUTING_SKILL"; then
  printf 'FAIL  brainstorming still names the retired Direct PR route\n' >&2
  exit 1
fi
if rg -qF 'workflow-routing' "$ROUTING_SKILL"; then
  printf 'FAIL  brainstorming must not delegate route ownership to workflow-routing\n' >&2
  exit 1
fi

test -f "$DIRECT_DEVELOPMENT_SKILL"
rg -qF 'name: direct-development' "$DIRECT_DEVELOPMENT_SKILL"
rg -qF 'approved bounded design' "$DIRECT_DEVELOPMENT_SKILL"
rg -qF '${TMPDIR:-/tmp}' "$DIRECT_DEVELOPMENT_SKILL"
rg -qF 'mktemp -d' "$DIRECT_DEVELOPMENT_SKILL"
rg -qF 'Plan: /absolute/path/to/plan.md' "$DIRECT_DEVELOPMENT_SKILL"
rg -qF 'Change:' "$DIRECT_DEVELOPMENT_SKILL"
rg -qF 'Touch:' "$DIRECT_DEVELOPMENT_SKILL"
rg -qF 'Verify:' "$DIRECT_DEVELOPMENT_SKILL"
rg -qF 'Boundary:' "$DIRECT_DEVELOPMENT_SKILL"
rg -qF 'superpowers:test-driven-development' "$DIRECT_DEVELOPMENT_SKILL"
rg -qF 'already approved' "$DIRECT_DEVELOPMENT_SKILL"
rg -qF 'materially change' "$DIRECT_DEVELOPMENT_SKILL"
if rg -qiF 'mini-planning' "$DIRECT_DEVELOPMENT_SKILL"; then
  printf 'FAIL  Direct Development still delegates to Mini Planning\n' >&2
  exit 1
fi
rg -qF 'display_name: "superpowers:direct-development"' "$DIRECT_DEVELOPMENT_METADATA"
rg -qF 'default_prompt: "Use $superpowers:direct-development for this localized change."' "$DIRECT_DEVELOPMENT_METADATA"

test -f "$MICRO_CHANGE_SKILL"
rg -qF 'name: micro-change' "$MICRO_CHANGE_SKILL"
rg -qF 'superpowers:using-git-worktrees' "$MICRO_CHANGE_SKILL"
rg -qF 'superpowers:test-driven-development' "$MICRO_CHANGE_SKILL"
rg -qF 'Visual-only changes skip TDD' "$MICRO_CHANGE_SKILL"
rg -qF 'authentic before-and-after visual evidence' "$MICRO_CHANGE_SKILL"
rg -qF 'Do not dispatch subagents' "$MICRO_CHANGE_SKILL"
rg -qF 'no temporary plan file' "$MICRO_CHANGE_SKILL"
rg -qF 'upgrade to Direct Development' "$MICRO_CHANGE_SKILL"
if rg -qF 'mktemp -d' "$MICRO_CHANGE_SKILL"; then
  printf 'FAIL  Micro Change creates a temporary plan\n' >&2
  exit 1
fi
rg -qF 'display_name: "superpowers:micro-change"' "$MICRO_CHANGE_METADATA"
rg -qF 'default_prompt: "Use $superpowers:micro-change for this approved tiny change."' "$MICRO_CHANGE_METADATA"

python3 - "$REPO_ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for relative_path in (
    ".claude-plugin/marketplace.json",
    ".agents/plugins/marketplace.json",
):
    document = json.loads((root / relative_path).read_text())
    assert document["name"] == "bmurgic-superpowers", relative_path
PY

test -x "$INSTALLER"

mkdir -p \
  "$TEST_ROOT/bin" \
  "$TEST_ROOT/codex" \
  "$TEST_ROOT/claude/skills/direct-development" \
  "$TEST_ROOT/claude/skills/micro-change" \
  "$TEST_ROOT/claude/skills/mini-planning" \
  "$TEST_ROOT/agents/skills/direct-development" \
  "$TEST_ROOT/agents/skills/micro-change" \
  "$TEST_ROOT/agents/skills/mini-planning"
cat >"$TEST_ROOT/bin/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'codex|CODEX_HOME=%s|%s\n' "${CODEX_HOME:-}" "$*" >>"$INSTALL_LOG"
case "$*" in
  'plugin list --json')
    if [ "${PERSONAL_INSTALLED:-0}" = 1 ]; then
      printf '%s\n' '{"installed":[{"pluginId":"superpowers@bmurgic-superpowers"}]}'
    else
      printf '%s\n' '{"installed":[{"pluginId":"superpowers@superpowers-marketplace"}]}'
    fi
    ;;
  'plugin marketplace list --json')
    if [ "${PERSONAL_INSTALLED:-0}" = 1 ]; then
      printf '%s\n' '{"marketplaces":[{"name":"bmurgic-superpowers"}]}'
    else
      printf '%s\n' '{"marketplaces":[{"name":"superpowers-marketplace"}]}'
    fi
    ;;
esac
SH
cat >"$TEST_ROOT/bin/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'claude|CLAUDE_CONFIG_DIR=%s|%s\n' "${CLAUDE_CONFIG_DIR:-}" "$*" >>"$INSTALL_LOG"
case "$*" in
  'plugin list --json')
    if [ "${PERSONAL_INSTALLED:-0}" = 1 ]; then
      printf '%s\n' '[{"id":"superpowers@bmurgic-superpowers"}]'
    else
      printf '%s\n' '[{"id":"superpowers@superpowers-marketplace"}]'
    fi
    ;;
  'plugin marketplace list --json')
    if [ "${PERSONAL_INSTALLED:-0}" = 1 ]; then
      printf '%s\n' '[{"name":"bmurgic-superpowers"}]'
    else
      printf '%s\n' '[{"name":"superpowers-marketplace"}]'
    fi
    ;;
esac
SH
chmod +x "$TEST_ROOT/bin/codex" "$TEST_ROOT/bin/claude"

INSTALL_LOG="$TEST_ROOT/install.log"
export INSTALL_LOG
PATH="$TEST_ROOT/bin:$PATH" "$INSTALLER" \
  --codex-home "$TEST_ROOT/codex" \
  --claude-config-dir "$TEST_ROOT/claude" \
  --agents-skills-dir "$TEST_ROOT/agents/skills"

test ! -e "$TEST_ROOT/claude/skills/direct-development"
test ! -e "$TEST_ROOT/claude/skills/micro-change"
test ! -e "$TEST_ROOT/claude/skills/mini-planning"
test ! -e "$TEST_ROOT/agents/skills/direct-development"
test ! -e "$TEST_ROOT/agents/skills/micro-change"
test ! -e "$TEST_ROOT/agents/skills/mini-planning"

rg -qF "codex|CODEX_HOME=$TEST_ROOT/codex|plugin marketplace add $REPO_ROOT" "$INSTALL_LOG"
rg -qF "codex|CODEX_HOME=$TEST_ROOT/codex|plugin add superpowers@bmurgic-superpowers" "$INSTALL_LOG"
rg -qF "codex|CODEX_HOME=$TEST_ROOT/codex|plugin remove superpowers@superpowers-marketplace" "$INSTALL_LOG"
rg -qF "codex|CODEX_HOME=$TEST_ROOT/codex|plugin marketplace remove superpowers-marketplace" "$INSTALL_LOG"
rg -qF "claude|CLAUDE_CONFIG_DIR=$TEST_ROOT/claude|plugin marketplace add $REPO_ROOT" "$INSTALL_LOG"
rg -qF "claude|CLAUDE_CONFIG_DIR=$TEST_ROOT/claude|plugin install superpowers@bmurgic-superpowers --scope user" "$INSTALL_LOG"
rg -qF "claude|CLAUDE_CONFIG_DIR=$TEST_ROOT/claude|plugin uninstall superpowers@superpowers-marketplace" "$INSTALL_LOG"
rg -qF "claude|CLAUDE_CONFIG_DIR=$TEST_ROOT/claude|plugin marketplace remove superpowers-marketplace" "$INSTALL_LOG"

: >"$INSTALL_LOG"
PERSONAL_INSTALLED=1 PATH="$TEST_ROOT/bin:$PATH" "$INSTALLER" \
  --codex-home "$TEST_ROOT/codex" \
  --claude-config-dir "$TEST_ROOT/claude" \
  --agents-skills-dir "$TEST_ROOT/agents/skills"

rg -qF "codex|CODEX_HOME=$TEST_ROOT/codex|plugin remove superpowers@bmurgic-superpowers" "$INSTALL_LOG"
rg -qF "codex|CODEX_HOME=$TEST_ROOT/codex|plugin add superpowers@bmurgic-superpowers" "$INSTALL_LOG"
rg -qF "claude|CLAUDE_CONFIG_DIR=$TEST_ROOT/claude|plugin marketplace update bmurgic-superpowers" "$INSTALL_LOG"
rg -qF "claude|CLAUDE_CONFIG_DIR=$TEST_ROOT/claude|plugin uninstall superpowers@bmurgic-superpowers" "$INSTALL_LOG"
rg -qF "claude|CLAUDE_CONFIG_DIR=$TEST_ROOT/claude|plugin install superpowers@bmurgic-superpowers --scope user" "$INSTALL_LOG"

printf 'PASS  personal fork routing and dual-client installer\n'
