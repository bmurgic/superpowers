# Pi Tool Mapping

Skills speak in actions ("dispatch a subagent", "create a todo", "read a file"). On Pi these resolve to the tools below.

| Action skills request | Pi equivalent |
| --- | --- |
| Dispatch a subagent (`Subagent (general-purpose):` template) | Use an installed subagent tool such as `subagent` from `pi-subagents` if available |
| Task tracking ("create a todo", "mark complete") | Use an installed todo/task tool if available, otherwise track tasks in the plan or `TODO.md` |

## Subagents

Pi core does not ship a standard subagent tool. The `pi-subagents` package is a strong optional companion and provides a `subagent` tool with single-agent, chain, parallel, async, forked-context, and resume/status workflows. If no subagent tool is available, do not fabricate `Task` calls; execute sequentially in the current session or explain that the optional subagent capability is not installed.

## Task lists

Pi core does not ship a standard task-list tool. If a todo/task extension is installed, use its documented tool. Otherwise use Superpowers plan files, checklists in Markdown, or a repo-local `TODO.md` for task tracking. Older Superpowers docs may refer to `TodoWrite`; treat that as the task-tracking action above.

## Custom Superpowers roles

Install or refresh the 18 Codex-derived specialist roles with `python3 scripts/install-pi-agents.py` from the personal Superpowers source checkout. Verify generated files against their authoritative Codex TOMLs with the same command plus `--check`.

Before specialist dispatch, use `subagent({ action: "list", agentScope: "user", capabilities: true })` and verify the exact canonical role name, user source, model and thinking. Dispatch with `agentScope: "user"` so legacy `.agents/skills` Markdown cannot masquerade as project agents. Never substitute a builtin worker alias for implementer or a skill file for gauntlet-driven-development. Missing custom roles block the workflow until installation is repaired.

Use `subagent({ agent: "implementer", agentScope: "user", async: true, task: "<approved bounded task and brief path>" })` for a fresh implementer. Preserve role model and thinking defaults. The returned run ID identifies the execution. Read status with `action: "status"`; inspect retained children with `action: "children.list"`. Resume only a retained child marked resumable with `action: "resume", agentScope: "user", id: "<latest run ID>", message: "<follow-up>"`. Resume returns a new receipt, so retain the newest run ID. Use the installed tool guide for exact status/wait parameters, rather than translating Codex task IDs into Pi IDs.

Plan-validator alone enables nested specialist delegation. Its three checker roles run with fresh context and their own pinned model settings. Children inherit skills, repository context, and the current managed global system instructions through the child-only context extension. Read-only specialist tools omit write and edit, but bash remains available for their required inspections and tests. Their no-write contracts are behavioral restrictions because Pi does not supply Codex filesystem sandboxing.

The dispatch guard requires user scope for canonical roles and retained resumes, checks task/chain scope overrides, and runs in plan-validator children too. Scripted workflows are blocked because their child JavaScript can override top-level scope without another tool call. Use separate direct async calls without waiting between launches.

Custom roles explicitly disable Pi package acceptance attestation because the GDD controller validates their source-contract reports. This preserves every required review, mutation and E2E gate. Successful Pi execution alone does not approve a GDD task. Do not override the role acceptance policy with the package reviewer schema.
