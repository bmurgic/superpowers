import { existsSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { homedir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

type Dispatch = {
	agent?: string;
	agentScope?: string;
	action?: string;
	resume?: string;
	workflowScript?: string;
	tasks?: Dispatch[];
	chain?: Dispatch[];
};

export function registerSpecialistPreflight(pi: ExtensionAPI) {
	pi.on("tool_call", async (event) => {
		if (event.toolName !== "subagent") {
			return;
		}
		if (!isDispatchInput(event.input)) {
			return { block: true, reason: "NEEDS_CONTEXT: Invalid subagent dispatch structure." };
		}
		const input = event.input;
		const isDispatch = input.agent !== undefined || input.tasks !== undefined || input.chain !== undefined || input.workflowScript !== undefined || input.resume !== undefined || input.action === "resume";
		if (!isDispatch) {
			return;
		}
		const scopeError = validateDispatchScope(input);
		if (scopeError) {
			return { block: true, reason: `NEEDS_CONTEXT: ${scopeError}` };
		}
		try {
			const agentDir = process.env.PI_CODING_AGENT_DIR || resolve(homedir(), ".pi/agent");
			if (!readFileSync(resolve(agentDir, "APPEND_SYSTEM.md"), "utf8").trim()) {
				throw new Error("Managed APPEND_SYSTEM.md is empty");
			}
			execFileSync("python3", [resolve(packageRoot, "scripts/install-pi-agents.py"), "--check", "--destination", resolve(agentDir, "agents")], { encoding: "utf8", timeout: 10000, stdio: "pipe" });
		} catch (error) {
			return { block: true, reason: `NEEDS_CONTEXT: Specialist launch blocked. Restore the managed global instructions and regenerate the Codex-derived Pi roles. ${String(error)}` };
		}
	});
}

function validateDispatchScope(input: Dispatch, inheritedScope?: string): string | undefined {
	// Script children can override workflow defaults without another tool_call.
	// Direct async calls keep every effective scope inspectable before launch.
	if (input.workflowScript !== undefined) {
		return "workflowScript cannot verify specialist scope. Use separate direct async calls with agentScope: user.";
	}
	const scope = input.agentScope ?? inheritedScope;
	const isCanonicalRole = typeof input.agent === "string" && /^[a-z][a-z-]*$/.test(input.agent) && existsSync(resolve(homedir(), ".codex/agents", `${input.agent}.toml`));
	const isResume = input.action === "resume" || input.resume !== undefined;
	if ((isCanonicalRole || isResume) && scope !== "user") {
		return "Canonical specialists and retained resumes require explicit agentScope: user. Project and default both scope cannot verify the role contract.";
	}
	for (const child of [...(input.tasks ?? []), ...(input.chain ?? [])]) {
		const error = validateDispatchScope(child, scope);
		if (error) {
			return error;
		}
	}
}

function isDispatchInput(value: unknown): value is Dispatch {
	if (typeof value !== "object" || value === null || Array.isArray(value)) {
		return false;
	}
	if ("agent" in value && typeof value.agent !== "string") {
		return false;
	}
	if ("agentScope" in value && typeof value.agentScope !== "string") {
		return false;
	}
	if ("action" in value && typeof value.action !== "string") {
		return false;
	}
	if ("resume" in value && typeof value.resume !== "string") {
		return false;
	}
	if ("workflowScript" in value && typeof value.workflowScript !== "string") {
		return false;
	}
	if ("tasks" in value && (!Array.isArray(value.tasks) || !value.tasks.every(isDispatchInput))) {
		return false;
	}
	if ("chain" in value && (!Array.isArray(value.chain) || !value.chain.every(isDispatchInput))) {
		return false;
	}
	return true;
}
