import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import extension from '../../.pi/extensions/child-global-context.ts';

test('child system context is live, deduplicated and required', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'pi-child-context-'));
  const previous = process.env.PI_CODING_AGENT_DIR;
  process.env.PI_CODING_AGENT_DIR = directory;
  const handlers = new Map();
  const messages = [];
  extension({ on(event, callback) { handlers.set(event, callback); }, sendMessage(message) { messages.push(message); } });
  const handler = handlers.get('before_agent_start');
  assert.equal((await handlers.get('tool_call')({ toolName: 'subagent', input: { agent: 'validator-tests', agentScope: 'project' } })).block, true);
  try {
    writeFileSync(join(directory, 'APPEND_SYSTEM.md'), 'SCR = simplify');
    assert.deepEqual(await handler({ systemPrompt: 'role' }), { systemPrompt: 'role\n\nSCR = simplify' });
    assert.equal(await handler({ systemPrompt: 'role\n\nSCR = simplify' }), undefined);
    writeFileSync(join(directory, 'APPEND_SYSTEM.md'), 'REF = references');
    assert.deepEqual(await handler({ systemPrompt: 'role' }), { systemPrompt: 'role\n\nREF = references' });
    rmSync(join(directory, 'APPEND_SYSTEM.md'));
    await assert.rejects(handler({ systemPrompt: 'role' }), /ENOENT/);
    assert.deepEqual(await handlers.get('input')(), { action: 'handled' });
    assert.match(messages[0].content, /Child launch blocked/);
  } finally {
    if (previous === undefined) delete process.env.PI_CODING_AGENT_DIR;
    else process.env.PI_CODING_AGENT_DIR = previous;
    rmSync(directory, { recursive: true });
  }
});
