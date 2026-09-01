---
name: openspec-gdd
description: Use when an approved design selects OpenSpec GDD before creating or completing the OpenSpec change
---

# OpenSpec GDD

OpenSpec GDD is ready only when the selected schema and complete bridge planning handoff have both been verified.

## Route entry

1. Run the installed `openspec-gdd` skill's absolute `scripts/require-bridge-schema` path from the active project root.
2. If it fails, stop before creating a change. Report its error and preserve the OpenSpec GDD selection. Do not retry with the default schema.
3. Use the installed `openspec-propose` entry as the authoritative procedure. Follow its Steps 1–3 with the selected `superpowers-bridge` schema and exact command `openspec new change <change-name> --schema superpowers-bridge`.
4. Immediately verify the created `.openspec.yaml` contains the exact top-level line `schema: superpowers-bridge`.
5. Resume `openspec-propose` at Step 4 against that just-created change to generate every required artifact.

## Planning handoff

Generic OpenSpec validation is structural evidence, not GDD readiness.

After planning completes:

1. Run `openspec validate <change-name> --strict`.
2. Then, from the installed `gauntlet-driven-development` skill directory, run `scripts/gdd-readiness CHANGE_DIRECTORY`.
3. State the change is ready for GDD only after both commands exit 0.

If either command fails, report the defects and return to planning. Do not invoke GDD, stock SDD, or another route.

## Red flags

- Creating the change before schema discovery passes
- Omitting `--schema superpowers-bridge`
- Treating `spec-driven` as close enough
- Calling `openspec validate --strict` a GDD readiness check
- Claiming readiness before `gdd-readiness` passes

Any red flag means stop and restore the selected OpenSpec GDD route.
