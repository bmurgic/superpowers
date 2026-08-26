#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ROUTING_SKILL="$REPO_ROOT/skills/brainstorming/SKILL.md"
DIRECT_DEVELOPMENT_SKILL="$REPO_ROOT/skills/direct-development/SKILL.md"
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
rg -qF 'OpenSpec GDD' "$ROUTING_SKILL"
rg -qF 'bare Superpowers plan' "$ROUTING_SKILL"
rg -qF 'Direct Development' "$ROUTING_SKILL"
rg -qF 'superpowers:direct-development' "$ROUTING_SKILL"
rg -qF 'Micro Change' "$ROUTING_SKILL"
rg -qF 'superpowers:micro-change' "$ROUTING_SKILL"
rg -qF 'I suggest <route> because <one short reason>.' "$ROUTING_SKILL"
rg -qF 'explicitly invoked' "$ROUTING_SKILL"
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
