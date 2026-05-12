# Project Constitution

<!--
This is the constitution for the attest repo itself.
It uses the attest CLAUDE.md template because this repo eats its own dog food.
-->

## What this codebase is

The attest workflow distribution repo. Holds the canonical source of the slash commands, the pre-commit hook, the claude-md-architect skill, and supporting docs. Designed to be installed into other repos via `./scripts/install.sh`.

**Project type:** library
<!-- "library" because this repo is consumed by other repos via install.sh -->

**Backend language:** none
**Frontend language:** none
**Contract pair name:** n/a
<!-- This repo has no runtime API surface. /contract is unlikely to ever
     run against this repo's own specs. The fields are documented for
     completeness so the skill knows what's intentional. -->

## Non-negotiable invariants

- The source of truth for commands, the skill, and the hook is `dist/`. `.claude/` is a generated copy.
- `.claude/` must always be in sync with `dist/` at commit time. Verified by `./scripts/verify-sync.sh` in CI.
- `dist/commands/contract_hash.py` is reference documentation only. The hash algorithm is re-implemented inline in `dist/commands/contract.md`. If the algorithm changes, BOTH files must be updated together — drift between them is a correctness bug.
- The pre-commit hook in `dist/hooks/pre-commit` is portable bash 4+. No GNU-specific flags, no dependencies beyond `git`, `grep`, `find`, `cmp`. Verified against the 5 test scenarios.
- The skill body (`dist/skill/claude-md-architect/SKILL.md`) is ≤500 lines. Detail goes into `references/` files which load on demand.
- No file under `dist/` exceeds 500 lines without a documented reason. Long files indicate something belongs in a reference.

## Conventions worth following

- Commit messages reference a spec or fix when changes touch `dist/` (the pre-commit hook will block otherwise).
- One concern per file. The `/spec` command does spec drafting; it does not also do compilation. Resist the urge to merge.
- Markdown formatting: keep lines under ~100 chars where natural; don't reformat existing content just to "neaten" it.
- Shell scripts use `set -euo pipefail` and are tested before commit.

## Recommended model per command

Each attest slash command has a `recommended-model` frontmatter field. The split:

| Command             | Recommended |
|---------------------|-------------|
| `/spec`             | sonnet      |
| `/contract`         | sonnet      |
| `/work`             | opus        |
| `/ship`             | opus        |
| `/check`            | sonnet      |
| `/fix`              | opus        |
| `/investigate`      | opus        |
| `/encode-lesson`    | opus        |
| `/review-decisions` | sonnet      |

Advisory, not enforced. Claude Code uses whatever model the user has selected. The ledger captures the model used per session for divergence analysis.

## How to verify work is done

- `./scripts/verify-sync.sh` passes (`.claude/` matches `dist/`)
- `bash -n dist/hooks/pre-commit` — no syntax errors
- `bash -n scripts/install.sh scripts/sync-local.sh scripts/verify-sync.sh dist/contract/breaking-change-check.sh` — no syntax errors
- `python3 dist/commands/contract_hash.py dist/commands/test-fixtures/spec-before.md` and `...spec-after.md` produce identical output (hash mechanism invariant)
- `python3 dist/ledger/attest_ledger.py log session_start command='"smoke"' --quiet && python3 dist/ledger/attest_ledger.py rebuild-index` — ledger smoke test
- `python3 -c "import py_compile; py_compile.compile('dist/contract/breaking-change-fallback.py', doraise=True)"` — breaking-change detector syntax
- All `*.md` files under `dist/` and `docs/` parse as well-formed markdown (no broken links to non-existent reference files)

## Where things live

- `dist/` — installable artifacts (source of truth)
- `dist/commands/` — eight slash command prompts
- `dist/contract/` — breaking-change detection helpers (bash + Python fallback)
- `dist/ledger/` — observability ledger (attest_ledger.py, ledger.sh, HOW-TO-LOG.md)
- `.claude/` — generated local copy, synced from `dist/`
- `docs/` — user-facing workflow documentation
- `examples/` — worked example specs and fixes
- `scripts/` — install, sync, verify
- `.github/` — issue templates, CI workflows, contributing guide
- `specs/` — spec files for changes to *this* repo (uses its own workflow)
- `fixes/` — fix files for bugs in *this* repo

## Domain glossary

- **dist/** — distribution directory; canonical source of files that get installed into other repos
- **The Wall** — the pre-commit hook that enforces spec/fix linkage on commits touching production code
- **Drift** — a state where spec, contract artifacts, and code disagree with each other
- **Hash-locked contract** — generated artifacts carry the SHA-256 hash of the spec's Contract surface section; `/work` refuses to proceed on mismatch
- **§ref** — traceability comment linking code to a spec or fix (e.g. `§ref:specs/2026-05-12-foo.md`)
- **Case 1/2/3/4** — the four-case classification for bug fixes, used by `/fix`
