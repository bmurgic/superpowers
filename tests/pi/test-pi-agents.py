import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[2] / 'scripts/install-pi-agents.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class PiAgentsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / 'source'
        self.source.mkdir()
        self.destination = Path(self.temp.name) / 'agents'
        (self.source / 'implementer-contract.md').write_text('contract')
        for name in installer.ROLE_NAMES:
            (self.source / f'{name}.toml').write_text(f'''name = "{name}"
description = "Role description"
model = "gpt-5.6-sol"
model_reasoning_effort = "xhigh"
sandbox_mode = "workspace-write"
developer_instructions = """adaptation\n<!-- SOURCE_BODY_BEGIN: source -->\nVerbatim behavior.\n"""
''')

    def test_install_preserves_contract_and_runtime_fields(self):
        installer.install(self.source, self.destination)
        installer.install(self.source, self.destination, check=True)
        self.assertEqual(len(list(self.destination.glob('*.md'))), 18)
        scout = (self.destination / 'scout.md').read_text()
        for value in ['name: "scout"', 'thinking: "xhigh"', 'model: "openai-codex/gpt-5.6-sol"', 'inheritGlobalContext: true', 'inheritSkills: true', 'tools: "read, grep, find, ls, bash"']:
            self.assertIn(value, scout)
        self.assertTrue(scout.endswith('Verbatim behavior.\n'))
        validator = (self.destination / 'plan-validator.md').read_text()
        self.assertIn('allowNestedSubagents: true', validator)
        self.assertIn('agentScope: "user"', validator)
        self.assertNotIn('allowNestedSubagents:', scout)

    def test_custom_roles_delegate_acceptance_to_gdd_controller(self):
        installer.install(self.source, self.destination)
        for name in installer.ROLE_NAMES:
            content = (self.destination / f'{name}.md').read_text()
            acceptance_line = next(line for line in content.splitlines() if line.startswith('acceptance: '))
            policy = json.loads(acceptance_line.removeprefix('acceptance: '))
            self.assertEqual(policy['level'], 'none')
            self.assertIn('GDD controller', policy['reason'])
            self.assertIn('review, mutation and E2E gates remain required', policy['reason'])

    def test_refuses_unmanaged_collision_before_writing(self):
        self.destination.mkdir()
        (self.destination / 'scout.md').write_text('user owned')
        with self.assertRaisesRegex(ValueError, 'unmanaged'):
            installer.install(self.source, self.destination)
        self.assertEqual(len(list(self.destination.iterdir())), 1)

    def test_missing_role_fails_closed(self):
        (self.source / 'implementer.toml').unlink()
        with self.assertRaisesRegex(ValueError, 'Role set mismatch'):
            installer.install(self.source, self.destination)

    def test_check_detects_drift(self):
        installer.install(self.source, self.destination)
        with (self.destination / 'scout.md').open('a') as output:
            output.write('drift')
        with self.assertRaisesRegex(ValueError, 'stale'):
            installer.install(self.source, self.destination, check=True)


if __name__ == '__main__':
    unittest.main()
