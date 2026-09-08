import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { registerSpecialistPreflight } from "../lib/specialist-preflight.ts";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// pi-subagents supplies appendSystemPrompt explicitly, suppressing Pi's normal
// APPEND_SYSTEM.md discovery. Restore the live operator layer for children only.
export default function childGlobalContext(pi: ExtensionAPI) {
	registerSpecialistPreflight(pi);
	pi.on("input", async () => {
		try {
			readGlobalInstructions();
		} catch (error) {
			pi.sendMessage({ customType: "superpowers-context-error", content: `NEEDS_CONTEXT: Child launch blocked: ${String(error)}`, display: true });
			return { action: "handled" as const };
		}
	});
	pi.on("before_agent_start", async (event) => {
		const instructions = readGlobalInstructions();
		if (event.systemPrompt.includes(instructions)) {
			return;
		}
		return { systemPrompt: `${event.systemPrompt}\n\n${instructions}` };
	});
}

function readGlobalInstructions(): string {
	const agentDir = process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
	const instructions = readFileSync(join(agentDir, "APPEND_SYSTEM.md"), "utf8");
	if (!instructions.trim()) {
		throw new Error("Managed APPEND_SYSTEM.md is empty");
	}
	return instructions;
}
