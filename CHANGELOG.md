# Changelog

All notable changes to this project will be documented in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once it reaches 1.0.

## [Unreleased]

### Added
- **New command: `/investigate`**. Structured investigation of failures (compile errors, runtime errors, test failures, broken CI, production incidents). Produces an investigation file under `investigations/` capturing observed symptoms, reproduction steps, hypotheses, ruled-out causes, evidence, and the root cause once found. The investigation file feeds into `/fix` via the new `--from-investigation` flag.
- **`/fix --from-investigation <file>` flag.** Pre-populates the fix file's "What was wrong" and "Root cause" sections from a completed investigation. Refuses to run if the investigation status is not `root-cause-identified`.
- **`/work` iteration discipline for compile/test failures.** Explicit guidance: iterate up to ~3 attempts with different hypotheses, then stop and escalate. Never disable tests, skip assertions, or relax invariants to make failures pass.
- **Pre-commit hook accepts `investigations/*.md` linkage** in addition to `specs/` and `fixes/`. A commit that touches `src/` and stages an investigation file passes the Wall.
- **New directory: `investigations/`**. Created by `install.sh`. Verified by the 6-scenario hook test in CI.

### Why this addition
Runtime errors and broken builds are the most common bug shape, and the previous workflow had no first-class place for the *investigation phase*. `/fix` required a known root cause, but most bugs start unknown. Without `/investigate`, the discovery phase lived in Slack threads and got lost. The trigger for adding this command: every real bug fix in practice starts with an investigation that the workflow previously hid.

### Added (previous)
- **New skill: `spec-reverse-engineer`**. Produces attest spec files from existing material: source code (Python, Java, TypeScript, others), OpenAPI/AsyncAPI definitions, BDD `.feature` files, Confluence/Notion-style design docs, or specs from other frameworks (GitHub Spec Kit, BMAD, Kiro, Tessl). Designed for adoption on existing codebases — most users don't start greenfield.
- Three reference files for the new skill: `from-code.md` (per-language extraction rules), `from-docs.md` (source-format migration tables), `examples.md` (three worked migrations: Spring Boot + tests, OpenAPI YAML, Confluence-style design doc).
- New spec status: `draft-reverse-engineered`. Distinct from `draft` to prevent accidentally running `/work` or `/contract` against an unreviewed reverse-engineered spec.
- README section: "Adopting attest on an existing codebase".

### Changed
- `install.sh` now installs both skills (`claude-md-architect` and `spec-reverse-engineer`) under `~/.claude/skills/`, plus the six commands (including the new `/investigate`).
- `sync-local.sh` and `verify-sync.sh` updated for the second skill and the new command.
- CI line-count check loops over both skills.
- Pre-commit hook updated for 6-scenario coverage (spec, fix, investigation, no-linkage, ref-in-code, bypass).

### Changed
- **Renamed project** from `two-commander` to `attest`. The old name was baggage from the source paper (the Two-Commander blog post) that proposed two human roles managing an agent fleet. That framing turned out to be rhetorical — what the workflow actually does is *attest*: every artifact (spec, contract, fix, §ref, commit) carries an attestation of something. The new name reflects the mechanism, not the metaphor.
- Updated all user-facing references (README, install messages, skill docstrings, template names) to use `attest`. Historical attribution to the Two-Commander source paper is preserved in the README's "Why this design, and what it isn't" section.

### Migration from `two-commander`
- Repo URL changes: `git clone https://github.com/<you>/attest.git`
- The `Two-Commander template` is now the `attest template`. The template shape itself is unchanged.
- Slash commands (`/spec`, `/contract`, `/work`, `/check`, `/fix`) are unchanged.
- Existing CLAUDE.md files using the template need no changes — only the name of the format changed, not its structure.

## [0.6.0] — 2026-05-12

### Added
- **Nested CLAUDE.md support** in `claude-md-architect` skill (Mode 4: Hierarchy)
  - Discovers all CLAUDE.md files in a repo, excluding `node_modules/`, `.git/`, `_generated/`
  - Audits root + nested for duplication and conflict
  - Designs new nested files for module boundaries — and refuses when boundaries don't warrant them
  - Splits a bloated root into root + nested
- New reference file: `nested-template.md` (lighter shape, ≤100 line cap)
- New reference file: `hierarchy-examples.md` with three worked examples
- README guidance on token reduction levers, with explicit rejection of caveman compression for command prompts

### Changed
- Root `CLAUDE.md.template` now documents the three token-reduction options (nested files, `@path` imports, plain references) with their tradeoffs
- `claude-md-architect` skill description widened to trigger on nested-CLAUDE.md and monorepo queries

## [0.5.0] — 2026-05-12

### Added
- **Bug-fix workflow** with `/fix` command
  - Four-case classification (code wrong / spec wrong / requirement changed / spec silent)
  - Fix artifacts in `fixes/` directory, separate from `specs/`
  - Spec versioning via supersession (originals preserved, never overwritten)
  - `--hot` mode for emergency fixes (compresses interaction, preserves all gates)
- `docs/bug-fix-workflow.md` with worked examples of all four cases
- Pre-commit hook now accepts `fixes/*.md` linkage in addition to `specs/*.md`

### Changed
- `/work` accepts either spec or fix files as input
- `§ref` traceability comments distinguish `§ref:specs/` vs `§ref:fixes/`

## [0.4.0] — 2026-05-12

### Fixed
- **Critical: hash mechanism bug.** Previous versions hashed the entire spec file, breaking immediately after `/contract` mutated the spec. Now hashes the normalised Contract surface section only.
- 8 other completeness issues in `/contract`: vague generation strategy, hand-waved Pact stubs, no idempotency contract, no breaking-change detection, no language detection, no partial-failure recovery, ambiguous slug filenames, unclear Pact pair naming, missing version bump rules

### Added
- Reference Python implementation `dist/commands/contract_hash.py`
- Test fixtures verifying hash stability across spec mutations
- Atomic write protocol for `_generated/` (staging directory)
- Per-language type-file shape rules (TS / Python / Java / Go / JS)
- CLAUDE.md fields: `Backend language`, `Frontend language`, `Contract pair name`

## [0.3.0] — 2026-05-12

### Added
- `/check` command for drift detection
- Drift checks wired into `/work` pre-flight and post-flight
- Pact provider verification in `/work --scope backend` post-flight
- `Project type` field in `CLAUDE.md` for scope defaulting

## [0.2.0] — 2026-05-12

### Added
- `/contract` command for full-stack work
- `--scope backend|frontend` argument on `/work`
- Contract surface section in spec template

## [0.1.0] — 2026-05-12

Initial release: `/spec`, `/work`, pre-commit hook, `claude-md-architect` skill.
