#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ROUTING_SKILL="$REPO_ROOT/skills/brainstorming/SKILL.md"
DIRECT_DEVELOPMENT_SKILL="$REPO_ROOT/skills/direct-development/SKILL.md"
OPENSPEC_GDD_SKILL="$REPO_ROOT/skills/openspec-gdd/SKILL.md"
OPENSPEC_GDD_METADATA="$REPO_ROOT/skills/openspec-gdd/agents/openai.yaml"
GDD_SKILL="$REPO_ROOT/skills/gauntlet-driven-development/SKILL.md"
FINISHING_SKILL="$REPO_ROOT/skills/finishing-a-development-branch/SKILL.md"
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
rg -qF 'bare Superpowers plan' "$ROUTING_SKILL"
rg -qF 'Direct Development' "$ROUTING_SKILL"
rg -qF 'direct-development' "$ROUTING_SKILL"
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
rg -qF 'fable-advisor:advise' "$GDD_SKILL"
rg -qF 'Round 1 uses `fixer`' "$GDD_SKILL"
rg -qF 'Rounds 2 through 5 use a fresh `fixer-max`' "$GDD_SKILL"
rg -qF 'one fix dispatch' "$GDD_SKILL"
rg -qF 'every affected slice' "$GDD_SKILL"
rg -qF 'repair-finish only after every affected slice reaches its replay endpoint' "$GDD_SKILL"
rg -qF 'one fresh whole-branch Branch Reviewer' "$GDD_SKILL"
rg -qF 'There is no second final fix wave' "$GDD_SKILL"
rg -qF 'Findings digest:' "$GDD_SKILL"

rg -qF 'Findings digest:' "$FINISHING_SKILL"
rg -qF 'These findings were left unchanged. Do you want action on any of them?' "$FINISHING_SKILL"
rg -qF '1. No, continue to the branch options.' "$FINISHING_SKILL"
rg -qF '2. Yes, create follow-up work for selected findings.' "$FINISHING_SKILL"
rg -qF '3. Ask Fable to reconsider selected findings.' "$FINISHING_SKILL"
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
  "$TEST_ROOT/claude/skills/mini-planning" \
  "$TEST_ROOT/agents/skills/direct-development" \
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
test ! -e "$TEST_ROOT/claude/skills/mini-planning"
test ! -e "$TEST_ROOT/agents/skills/direct-development"
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
