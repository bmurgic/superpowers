# Personal Superpowers fork

This repository tracks `obra/superpowers` and keeps a deliberately small
personal delta.

## Owned differences

1. `skills/brainstorming/SKILL.md` asks Brandon to select OpenSpec GDD, a bare
   Superpowers plan, Direct Development, or Micro Change after design approval.
   An explicitly invoked route command or skill selects its route without
   asking again.
2. The Claude and Codex marketplace names and the matching Codex manifest test
   use `bmurgic-superpowers`, which keeps the personal plugin distinct from the
   upstream marketplace.
3. `scripts/install-personal-fork` installs or refreshes the personal
   marketplace for both clients and removes the replaced upstream Superpowers
   installation.
4. `skills/direct-development/SKILL.md` implements an approved bounded design
   with a temporary recovery file, TDD, focused verification, and the standard
   branch-finishing menu. The installer removes retired loose copies of Direct
   Development, Micro Change, and Mini Planning so the plugin remains the only
   source.
5. `skills/micro-change/SKILL.md` implements an approved one-line code fix or
   visual-only adjustment in a worktree without a temporary plan or subagents.
   Code changes use TDD. Visual-only changes use authentic before-and-after
   evidence.

Everything else should remain aligned with upstream.

## Updating from upstream

1. Fetch and merge `upstream/main` into this fork.
2. Resolve conflicts only in the owned files above. Preserve upstream changes
   everywhere else.
3. Run `bash tests/personal-fork/test-personal-fork.sh` and the upstream test
   suite relevant to any conflicted files.
4. Review the complete fork delta against `upstream/main` before pushing.
5. Run the configuration repository's `scripts/provision-personal-superpowers`
   to update both installed clients.
