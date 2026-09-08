import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, '../..');
const packageJsonPath = resolve(repoRoot, 'package.json');
const extensionPath = resolve(repoRoot, '.pi/extensions/superpowers.ts');
const piToolsPath = resolve(repoRoot, 'skills/using-superpowers/references/pi-tools.md');

async function readPackageJson() {
  return JSON.parse(await readFile(packageJsonPath, 'utf8'));
}

async function loadExtension() {
  const handlers = new Map();
  const pi = {
    on(event, handler) {
      if (!handlers.has(event)) handlers.set(event, []);
      handlers.get(event).push(handler);
    },
  };
  const mod = await import(pathToFileURL(extensionPath).href + `?cachebust=${Date.now()}-${Math.random()}`);
  mod.default(pi);
  return { handlers };
}

function firstHandler(handlers, event) {
  const eventHandlers = handlers.get(event) ?? [];
  assert.equal(eventHandlers.length, 1, `expected one ${event} handler`);
  return eventHandlers[0];
}

function textOf(message) {
  if (typeof message.content === 'string') return message.content;
  return message.content
    .filter((part) => part.type === 'text')
    .map((part) => part.text)
    .join('\n');
}

test('package.json declares a pi package with skills and extension resources', async () => {
  const pkg = await readPackageJson();

  assert.equal(pkg.name, 'superpowers');
  assert.ok(pkg.keywords.includes('pi-package'));
  assert.deepEqual(pkg.pi.skills, ['./skills']);
  assert.deepEqual(pkg.pi.extensions, ['./.pi/extensions/superpowers.ts']);
});

test('extension registers lifecycle hooks without pre-compaction injection', async () => {
  const { handlers } = await loadExtension();

  for (const event of ['resources_discover', 'session_start', 'session_compact', 'context', 'agent_end']) {
    assert.equal((handlers.get(event) ?? []).length, 1, `missing ${event} handler`);
  }
  assert.equal((handlers.get('session_before_compact') ?? []).length, 0);
});

test('resources_discover contributes the bundled skills directory', async () => {
  const { handlers } = await loadExtension();
  const discover = firstHandler(handlers, 'resources_discover');

  const result = await discover({ type: 'resources_discover', cwd: repoRoot, reason: 'startup' }, {});

  assert.deepEqual(result.skillPaths, [resolve(repoRoot, 'skills')]);
});

test('startup context injects the bootstrap as one user message until agent_end', async () => {
  const { handlers } = await loadExtension();
  const sessionStart = firstHandler(handlers, 'session_start');
  const context = firstHandler(handlers, 'context');
  const agentEnd = firstHandler(handlers, 'agent_end');

  await sessionStart({ type: 'session_start', reason: 'startup' }, {});

  const originalMessages = [
    { role: 'user', content: [{ type: 'text', text: 'Let us make a react todo list' }], timestamp: 1 },
  ];
  const result = await context({ type: 'context', messages: originalMessages }, {});

  assert.equal(result.messages.length, 2);
  assert.equal(result.messages[0].role, 'user');
  assert.match(textOf(result.messages[0]), /You have superpowers/);
  assert.match(textOf(result.messages[0]), /Pi tool mapping/);
  assert.equal(result.messages[1], originalMessages[0]);

  const repeatedProviderRequest = await context({ type: 'context', messages: originalMessages }, {});
  assert.equal(repeatedProviderRequest.messages.length, 2);
  assert.match(textOf(repeatedProviderRequest.messages[0]), /You have superpowers/);

  const alreadyInjected = await context({ type: 'context', messages: result.messages }, {});
  assert.equal(alreadyInjected, undefined, 'bootstrap should not duplicate when already present');

  await agentEnd({ type: 'agent_end', messages: [] }, {});
  const afterEnd = await context({ type: 'context', messages: originalMessages }, {});
  assert.equal(afterEnd, undefined, 'startup bootstrap should clear after agent_end');
});

test('session_compact injects bootstrap after compaction summaries, not before compaction', async () => {
  const { handlers } = await loadExtension();
  const sessionCompact = firstHandler(handlers, 'session_compact');
  const context = firstHandler(handlers, 'context');

  await sessionCompact({ type: 'session_compact', compactionEntry: {}, fromExtension: false }, {});

  const summary = { role: 'compactionSummary', summary: 'Prior work summary', tokensBefore: 123, timestamp: 1 };
  const user = { role: 'user', content: [{ type: 'text', text: 'Continue' }], timestamp: 2 };
  const result = await context({ type: 'context', messages: [summary, user] }, {});

  assert.equal(result.messages.length, 3);
  assert.equal(result.messages[0], summary);
  assert.equal(result.messages[1].role, 'user');
  assert.match(textOf(result.messages[1]), /You have superpowers/);
  assert.equal(result.messages[2], user);
});

test('pi tools reference documents pi-specific mappings', async () => {
  assert.equal(existsSync(piToolsPath), true, 'pi-tools.md should exist');
  const text = await readFile(piToolsPath, 'utf8');

  // Assert against the mapping-table rows only. The surrounding prose mentions
  // these same tokens, so matching the whole file would still pass if the table
  // were deleted — the exact regression this test exists to catch.
  const rows = text.split('\n').filter((line) => line.startsWith('|'));
  assert.ok(
    rows.some((row) => /subagent/i.test(row)),
    'mapping table documents subagent dispatch',
  );
  assert.ok(
    rows.some((row) => /todo|task/i.test(row)),
    'mapping table documents task tracking',
  );
});

test('specialist preflight blocks missing managed context before dispatch', async () => {
  const previous = process.env.PI_CODING_AGENT_DIR;
  process.env.PI_CODING_AGENT_DIR = '/tmp/superpowers-nonexistent-context-test';
  try {
    const { handlers } = await loadExtension();
    const handler = handlers.get('tool_call')[0];
    const result = await handler({ toolName: 'subagent', input: { agent: 'scout', agentScope: 'user' } });
    assert.equal(result.block, true);
    assert.match(result.reason, /NEEDS_CONTEXT/);
    assert.equal(await handler({ toolName: 'subagent', input: { action: 'status' } }), undefined);
    assert.equal((await handler({ toolName: 'subagent', input: { action: 'resume', id: 'retained' } })).block, true);
  } finally {
    if (previous === undefined) delete process.env.PI_CODING_AGENT_DIR;
    else process.env.PI_CODING_AGENT_DIR = previous;
  }
});

test('canonical role scope is enforced for direct, nested, workflow and resume calls', async () => {
  const { handlers } = await loadExtension();
  const handler = handlers.get('tool_call')[0];
  const calls = [
    { agent: 'scout' },
    { agentScope: 'user', tasks: [null] },
    { agent: 'implementer', agentScope: 'project' },
    { agent: 'scout', agentScope: 'both' },
    { agentScope: 'user', tasks: [{ agent: 'scout', agentScope: 'project' }] },
    { agentScope: 'user', chain: [{ agent: 'scout', agentScope: 'both' }] },
    { agentScope: 'user', workflowScript: 'return runs.run("check", { agent: "scout", agentScope: "project" });' },
    { action: 'resume', id: 'retained' },
  ];
  for (const input of calls) {
    assert.equal((await handler({ toolName: 'subagent', input })).block, true, JSON.stringify(input));
  }
});

test('valid managed context reaches generated-role verification for launches and resumes', async () => {
  const { mkdtempSync, writeFileSync, readFileSync, rmSync } = await import('node:fs');
  const { tmpdir } = await import('node:os');
  const { execFileSync } = await import('node:child_process');
  const directory = mkdtempSync(resolve(tmpdir(), 'pi-role-preflight-'));
  const previous = process.env.PI_CODING_AGENT_DIR;
  process.env.PI_CODING_AGENT_DIR = directory;
  try {
    writeFileSync(resolve(directory, 'APPEND_SYSTEM.md'), 'Managed operator context.');
    execFileSync('python3', [resolve(repoRoot, 'scripts/install-pi-agents.py'), '--destination', resolve(directory, 'agents')]);
    const { handlers } = await loadExtension();
    const handler = handlers.get('tool_call')[0];
    const launch = { toolName: 'subagent', input: { agent: 'scout', agentScope: 'user' } };
    const resume = { toolName: 'subagent', input: { action: 'resume', id: 'retained', agentScope: 'user' } };
    assert.equal(await handler(launch), undefined);
    assert.equal(await handler(resume), undefined);
    const rolePath = resolve(directory, 'agents/scout.md');
    writeFileSync(rolePath, readFileSync(rolePath, 'utf8') + '\nChanged contract.');
    for (const call of [launch, resume]) {
      const result = await handler(call);
      assert.equal(result.block, true);
      assert.match(result.reason, /stale/);
    }
    for (const action of ['list', 'status']) {
      assert.equal(await handler({ toolName: 'subagent', input: { action } }), undefined);
    }
  } finally {
    if (previous === undefined) delete process.env.PI_CODING_AGENT_DIR;
    else process.env.PI_CODING_AGENT_DIR = previous;
    rmSync(directory, { recursive: true });
  }
});
