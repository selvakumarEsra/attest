# Contributing

Thanks for your interest in attest.

## Development setup

```bash
git clone https://github.com/<you>/attest.git
cd attest

# Sync the source-of-truth files into .claude/ for local Claude Code use
./scripts/sync-local.sh
```

Now open the repo in Claude Code. The five commands (`/spec`, `/contract`, `/work`, `/check`, `/fix`) and the `claude-md-architect` skill are available.

## The source of truth

**Always edit files under `dist/`.** Never edit `.claude/` directly — it's a generated copy. After editing `dist/`, run:

```bash
./scripts/sync-local.sh
```

This regenerates `.claude/`. CI verifies the two are in sync; PRs that change `dist/` without running sync will fail.

## Making changes

### Small fixes (typos, formatting, clarifications)

Just edit `dist/`, run sync, commit. The pre-commit hook may ask you to reference a spec or fix in the commit message; for trivial doc fixes, `git commit --no-verify -m "docs: fix typo"` is fine — these bypasses are visible in `git log` and reviewed during PR.

### Behavioural changes (new options, new commands, command logic changes)

These should go through this repo's own workflow:

1. `/spec <ticket>` — create a spec describing what you're changing
2. Optionally `/contract` if you're touching the command-prompt schema (e.g. adding a new field to `CLAUDE.md.template` that downstream commands read)
3. `/work specs/<your-spec>.md`
4. Commit with the spec staged

This dogfooding is the strongest signal that the workflow itself is usable.

### Bug fixes

Use `/fix`:

```
/fix <ticket> --against specs/<original-spec>.md
```

Classify the bug into one of the four cases (see `docs/bug-fix-workflow.md`).

## Style

- **Markdown:** keep lines under ~100 chars where natural; don't reformat existing content just to neaten it.
- **Bash:** `set -euo pipefail` at the top; quote variables; prefer `[[ ]]` over `[ ]`; test with `bash -n` before commit.
- **Command prompts:** explicit beats clever. We chose this hill in v4 — explicit instructions caught a real bug that compressed ones would have hidden.

## What we don't accept

- Caveman compression of command prompts (see README "Why this design" — explicit prompts are a deliberate choice)
- Personality/tone instructions in command prompts ("be helpful", "be concise") — that's user preferences, not project rules
- Generated content in `dist/` that should live in `_generated/` in target repos
- New commands without a documented "when to add it" trigger

## CI checks

The CI workflow runs:

1. `./scripts/verify-sync.sh` — `.claude/` matches `dist/`
2. Syntax checks on all shell scripts
3. Hash mechanism invariant test (the `contract_hash.py` reference)
4. Pre-commit hook 5-scenario test
5. Skill body line-count sanity (≤500 lines)

All five must pass.

## Reporting issues

Please use the issue templates under `.github/ISSUE_TEMPLATE/`. The two main categories:

- **Bug**: something doesn't work as documented
- **Workflow gap**: something isn't covered by the current commands and you've hit it on a real ticket

For workflow gaps, include the specific scenario you encountered. The trigger to add a new piece is "this came up on a real ticket and the current workflow couldn't handle it" — not "I imagine this would be useful".

## Releases

This repo follows a simple model: `dist/` is always installable from `main`. There are no tagged releases yet; install from `main` until v1.0.

Breaking changes to command prompts are noted in `CHANGELOG.md` (coming) and surfaced in PR descriptions. Until 1.0, breaking changes happen freely; after 1.0, they go through a deprecation cycle.
