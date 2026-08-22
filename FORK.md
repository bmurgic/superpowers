# Personal Superpowers fork

This repository tracks `obra/superpowers` and keeps a deliberately small
personal delta.

## Owned differences

1. `skills/brainstorming/SKILL.md` asks Brandon to select OpenSpec GDD, a bare
   Superpowers plan, or Direct Development after design approval. An explicitly
   invoked route command or skill selects its route without asking again.
2. The Claude and Codex marketplace names and the matching Codex manifest test
   use `bmurgic-superpowers`, which keeps the personal plugin distinct from the
   upstream marketplace.
3. `scripts/install-personal-fork` installs or refreshes the personal
   marketplace for both clients and removes the replaced upstream Superpowers
   installation.

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
