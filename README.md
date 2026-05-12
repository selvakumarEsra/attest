# attest

A spec-driven development workflow for [Claude Code](https://docs.claude.com/en/docs/claude-code), purpose-built for regulated full-stack engineering — where every change needs a traceable contract, every decision needs an audit trail, and every shipped feature needs to survive a regulator's question of "show me how this got here."

## Overview

attest treats specs, fixes, and investigations as **first-class artifacts** that drive both Claude and humans through the same pipeline. The spec is the contract; code is the build artifact. A pre-commit hook ("the Wall") refuses to let production code ship without linkage to one of these artifacts. An observability ledger records every command, decision, drift finding, and gate event into an append-only JSONL log that doubles as the AI-usage audit trail.

The system is nine slash commands, two skills, one pre-commit hook, an observability ledger, and a structural breaking-change detector. It installs into a target repo in seconds and operates entirely on local files — no external services, no managed platform, no vendor lock-in. The JSONL ledger is committed to your repo; the derived SQLite index is gitignored and rebuildable.

Where comparable approaches (Spec Kit, Kiro, BMAD, Tessl) lean toward elaborate frameworks with dozens of agent personas and orchestration concepts, attest is deliberately minimal in surface and opinionated in discipline. The right abstraction for "we need traceability and review gates and contract integrity" is not a platform — it's a small set of well-shaped artifacts and the tooling to enforce their boundaries.

## Capability matrix

| Capability | What attest provides | Where it lives |
|---|---|---|
| **Spec drafting** | `/spec` — date-slug spec files with Open Questions, Acceptance Criteria, optional Contract Surface | `dist/commands/spec.md` |
| **Full-stack contract compilation** | `/contract` — Contract Surface → OpenAPI + typed schemas + Pact stubs in `_generated/`. Hash-locked, idempotent, atomic. | `dist/commands/contract.md` |
| **Structural breaking-change detection** | OpenAPI diff against previous compilation: removed endpoints, type changes, new required fields, enum shrinkage. Uses `oasdiff` if installed, built-in Python fallback otherwise | `dist/contract/` |
| **Single-scope execution** | `/work --scope backend\|frontend` — scope-locked, with drift checks on entry/exit and 3-attempt iteration discipline | `dist/commands/work.md` |
| **Full-stack orchestration** | `/ship` — runs `/contract` then dispatches parallel backend+frontend `/work` via Task subagents, then `/check`. Parent/child session correlation in the ledger | `dist/commands/ship.md` |
| **Drift detection** | `/check` — four checks: hash mismatch, ticked-criterion traceability, code-without-spec-coverage, code-implies-spec divergence | `dist/commands/check.md` |
| **Structured failure investigation** | `/investigate` — captures evidence, hypotheses, what was ruled out, and the root cause. Statuses: open → root-cause-identified → closed-resolved | `dist/commands/investigate.md` |
| **Bug fixes against existing specs** | `/fix` — four-case classification (code wrong / spec wrong / new requirement / spec silent), `--hot` for incidents, `--from-investigation` for chained flows | `dist/commands/fix.md` |
| **Learning loop closure** | `/encode-lesson` — promotes a closed-resolved investigation's lesson into a durable invariant in CLAUDE.md (or nested CLAUDE.md, skill gotchas, command prompt). Stable lesson_id + bidirectional linkback | `dist/commands/encode-lesson.md` |
| **Human-in-loop decision review** | `/review-decisions` — surfaces decisions Claude logged during `/work`, lets human mark each as accepted / rejected / needs-redo with notes | `dist/commands/review-decisions.md` |
| **The Wall (pre-commit hook)** | Refuses commits touching `src/`, `lib/`, `app/` without spec-or-fix-or-investigation linkage. Accepts staged artifact, commit-message reference, or in-code `§ref:` comment. Bypasses via `--no-verify` logged separately | `dist/hooks/pre-commit` |
| **Observability ledger** | JSONL (committed, append-only) + SQLite (gitignored, rebuildable). 15 known event types. CLI: log, rebuild-index, query, summary, export-csv. Verified concurrent-safe at 20 parallel writers | `dist/ledger/` |
| **CLAUDE.md authoring & maintenance** | `claude-md-architect` skill — 4 modes (Greenfield, Conversion, Audit, Hierarchy for nested CLAUDE.md) | `dist/skill/claude-md-architect/` |
| **Spec backfill for existing code** | `spec-reverse-engineer` skill — code-only, docs-only, hybrid modes. Produces `draft-reverse-engineered` status that `/work` refuses without explicit review | `dist/skill/spec-reverse-engineer/` |
| **Model-version intent** | `recommended-model` frontmatter on every command (sonnet or opus). Advisory, not enforced; ledger captures actual model used | per-command frontmatter |

## Why this exists

attest was built for a specific use case: **developing full-stack applications inside a tier-1 bank**, under regulators (MAS in Singapore, comparable framings elsewhere — Fed SR 11-7, EBA, OSFI, APRA), where every line of code that ships needs to survive examination questions like:

- "How did this change get from a business requirement to production?"
- "What did your AI assistant decide that a human didn't explicitly tell it to decide?"
- "When the spec and the code disagreed, which one did your team trust?"
- "Show me your AI-usage inventory for Q3."
- "Did the team learn from incident X, and where is that lesson encoded so it can't happen the same way again?"

In a regulated bank context, you do not have the luxury of an unmarked code change. You do not have the luxury of a Claude session that produced output you cannot reconstruct. You do not have the luxury of "we'll write the post-mortem later." Every action needs to leave a paper trail that an external auditor — who does not trust you and does not trust AI — can follow.

### The problem

Off-the-shelf AI-assisted development workflows are built for startup tempo. They optimize for *fewer keystrokes between idea and shipped code*. In a bank, that optimization runs backward — the audit trail IS the value, and shortcuts that erase it are unacceptable. Specifically:

- **Specs and code drift silently.** A developer drafts a spec, Claude implements, the diff goes through review, but somewhere in the middle the spec stops matching what was built. Six months later, no one can tell whether the production behaviour matches the originally-agreed contract or some later mutation.
- **API contracts get broken by accident.** A backend dev edits an endpoint's response schema. Tests pass because they were updated alongside. A consumer team learns at deployment that a field they depended on is now a different type, or gone.
- **Claude's decisions vanish into diffs.** When Claude picks one library over another, handles an edge case the spec didn't specify, or modifies a verification step, those choices live inside multi-thousand-line PRs that no reviewer reads exhaustively. The trail records *what* was decided without recording *whether the human agreed*.
- **Bug fixes overwrite history.** A spec says X, production does Y, the fix updates the spec to say Y. Now the original disagreement — the audit-relevant fact that the system once promised X — is gone.
- **Investigations leak into incident retrospectives that no one revisits.** A team finds the root cause of an outage, ships a fix, writes a post-mortem doc, and three months later trips on the same class of bug because the lesson stayed in a meeting note and never became a durable invariant.
- **The AI-usage inventory is something teams have to manually reconstruct.** Regulators are increasingly asking "where do you use AI, for what, and with what governance?" — answering this from git commits and Slack threads is impossible at scale.
- **Different teams have different definitions of "done."** Backend says the endpoint works. Frontend says the integration is broken. Neither side has a contract artifact to point at; both sides have plausible spec-prose interpretations. The argument is unresolvable without a binding contract.
- **The pre-commit gate is either too lenient or annoyingly strict.** Either it lets anything through (audit gap), or it blocks emergency hotfixes in genuine incident scenarios (operational friction). What's needed is a gate that distinguishes "production code without paper trail" from "documentation tweak" automatically.
- **Full-stack work serializes badly.** Spec → contract compile → backend `/work` → frontend `/work` → integration check is four sequential Claude sessions when the backend and frontend pieces could trivially run in parallel against the same contract artifacts.

attest addresses each of these directly, in service of the same overarching goal: make the audit trail a byproduct of normal work rather than a separate compliance burden.

## Features

- **Artifact-centric pipeline.** Specs in `specs/`, fixes in `fixes/`, investigations in `investigations/`, compiled contract artifacts in `_generated/`. Each artifact carries traceability; code links back to its artifact via `§ref:` comments or commit messages.

- **The Wall — pre-commit traceability hook.** Refuses production-code commits without artifact linkage. Six acceptance scenarios cover staged artifacts, commit-message references, in-code `§ref:` comments, and deliberate `--no-verify` bypasses. Bypasses are logged separately so audit trail captures them honestly.

- **Hash-locked contracts.** SHA-256 over the normalised Contract Surface section of a spec, stamped into every generated artifact. `/work` recomputes and refuses to proceed on mismatch. Catches "spec edited after compile but artifacts not regenerated" as a hard error.

- **Structural breaking-change detection.** When `/contract` re-compiles, it diffs the previous OpenAPI artifact against the new one and classifies the change. Removed endpoints, type changes, new required fields, removed enum values, removed response codes — all flagged as breaking with explicit user confirmation required. Uses `oasdiff` if installed, falls back to a built-in Python detector covering ~80% of real-world cases.

- **Parallel full-stack orchestration via `/ship`.** Dispatches Task subagents in parallel for backend and frontend, each in an isolated context window, scope-locked. Cuts a 4-session manual sequence to one orchestrated invocation. Parent/child session correlation in the ledger.

- **Observability ledger with two storage layers.** Append-only JSONL (committed, durable, single source of truth) plus derived SQLite index (gitignored, queryable, rebuildable). 15 known event types covering session lifecycle, artifact lifecycle, decisions, drift, gates, subagents, verifications, lessons, breaking changes. CLI tools for summary reports and CSV export to BI tools.

- **Human-in-loop decision review.** Decisions Claude makes during `/work` are logged as `decision_logged` events. `/review-decisions` surfaces them, lets a human mark each as accepted, rejected, or needs-redo, and records the verdict as a `decision_reviewed` event. Original decision log is append-only; verdicts layer on top. Soft-reject design — `needs-redo` requires explicit re-invocation, not auto-redo.

- **Investigation → fix → learning loop.** `/investigate` for unknown failures (with status lifecycle: open → root-cause-identified → closed-resolved / closed-not-reproducible / closed-external), feeds into `/fix --from-investigation`. After the fix holds, `/encode-lesson` promotes the takeaway into a durable invariant in CLAUDE.md (or a nested CLAUDE.md, skill gotcha, or command prompt). Each encoded lesson carries a stable lesson_id and bidirectional linkback.

- **Four-case bug fix classification.** `/fix` makes you classify on entry: (1) code wrong, spec right; (2) spec wrong, code reasonable; (3) requirement evolved (redirect to /spec); (4) spec silent, behaviour emerged. Cases 2 and 4 create superseding specs — originals preserved as historical truth. Bugs do not overwrite specs.

- **Drift detection with four checks.** Hash mismatch, ticked-criterion-without-code-trace, code-changes-without-spec-coverage, code-implies-spec-divergence. Runs automatically on `/work` entry and exit; can be invoked manually anytime.

- **Reverse-engineering for existing codebases.** `spec-reverse-engineer` skill backfills specs from Python/Java/TypeScript/Go code, OpenAPI/AsyncAPI docs, BDD `.feature` files, Confluence docs, or other framework-style specs (Spec Kit, BMAD, Kiro, Tessl). Produces `draft-reverse-engineered` status that `/work` and `/contract` refuse without explicit human review — guards against bulk-generation that produces unreviewable output.

- **CLAUDE.md authoring with the `claude-md-architect` skill.** Four modes: Greenfield (new project), Conversion (existing repo with informal docs), Audit (existing CLAUDE.md needs review), Hierarchy (root + nested CLAUDE.md files in monorepos).

- **Model-version intent recorded per command.** Each command's frontmatter declares its `recommended-model` (sonnet or opus). Advisory, not enforced — the ledger captures the actual model used per session for divergence analysis. Reproducibility property without false enforcement.

- **MAS AIRG / SR 11-7-aligned audit substrate.** Not a complete AI risk governance program, but provides the artefacts examiners ask for: per-command usage inventory (sessions table), decisions inventory (decisions table with human verdicts), incident learnings inventory (lessons table), contract-change inventory (breaking_changes table). All queryable via SQL, exportable to CSV.

## Installation

attest installs into a target repo via a single shell script. The script is idempotent — re-running is safe.

### Prerequisites

- Git
- Python 3.9+ (for the ledger and contract helpers; pure stdlib, no external packages required)
- Claude Code installed and configured
- Optional but recommended: `oasdiff` for full OpenAPI 3.x breaking-change coverage:
  ```bash
  go install github.com/oasdiff/oasdiff@latest
  ```
  Without `oasdiff`, attest uses a built-in Python fallback that catches ~80% of real-world breaking changes.

### Install

```bash
# Clone attest
git clone https://github.com/<your-org>/attest.git
cd attest

# Install into your project
./scripts/install.sh /path/to/your/repo

# Preview what would change first, if you prefer
./scripts/install.sh /path/to/your/repo --dry-run
```

The installer does seven things, each clearly numbered in the output:

1. Drops in a `CLAUDE.md` template at the repo root (only if no `CLAUDE.md` exists)
2. Creates the artifact directories: `specs/`, `fixes/`, `investigations/`, `_generated/`, `.attest/ledger/`, `.attest/contract/`
3. Installs the nine slash commands to `.claude/commands/`
4. Installs the pre-commit hook to `.git/hooks/pre-commit`
5. Installs the observability ledger (`attest_ledger.py`, `ledger.sh`, `HOW-TO-LOG.md`) to `.attest/ledger/`
6. Installs the contract helpers (`breaking-change-check.sh`, `breaking-change-fallback.py`) to `.attest/contract/`, and detects whether `oasdiff` is on PATH
7. Installs the two skills (`claude-md-architect`, `spec-reverse-engineer`) to `~/.claude/skills/` (user-scoped; skip with `--skip-skill`)

### After installing

```bash
cd /path/to/your/repo

# Open CLAUDE.md and fill in the placeholders
$EDITOR CLAUDE.md

# Commit the new structure
git add CLAUDE.md .claude/ .attest/ specs/ fixes/ investigations/ _generated/.gitattributes
git commit -m "chore: install attest workflow"

# Open in Claude Code and you're ready
```

The `.attest/ledger/events.jsonl` file is committed (audit trail). The `.attest/ledger/index.db` SQLite file is gitignored (rebuildable derivative).

### Available install flags

```
./scripts/install.sh <target> [--dry-run] [--skip-hook] [--skip-skill] [--user-commands]
```

- `--dry-run` — preview without writing
- `--skip-hook` — don't install the pre-commit hook (rarely useful; defeats The Wall)
- `--skip-skill` — don't install skills user-scoped (for shared dev environments)
- `--user-commands` — install commands at `~/.claude/commands/` instead of project-scoped

## Quick start

Suppose you're building a notification-preferences endpoint for a bank's customer portal. Backend in Spring Boot, frontend in Angular. Compliance requires every change be linked to a spec.

### 1. Draft the spec

In Claude Code:

```
/spec NOTIF-247 customer notification preferences endpoint
```

Claude reads your `CLAUDE.md` for invariants, asks any clarifying questions, then drafts `specs/2026-05-12-notif-preferences.md` with sections for:
- Why
- What changes
- Acceptance criteria (per scope: backend, frontend, integration)
- Contract surface (the API spec)
- Open questions
- Out of scope

Edit the spec, resolve open questions, then commit:

```bash
git add specs/2026-05-12-notif-preferences.md
git commit -m "spec: NOTIF-247 customer notification preferences"
```

### 2. Ship the full-stack feature

```
/ship specs/2026-05-12-notif-preferences.md
```

`/ship` runs four stages in one orchestrated invocation:

```
Stage 1: /contract specs/2026-05-12-notif-preferences.md
  → Compiles Contract Surface to _generated/openapi/notif-prefs.yaml
  → Generates Spring Boot types and Angular TypeScript types
  → Generates Pact stub files for consumer-driven contract testing
  → Logs SHA-256 contract hash into spec metadata
  → Runs breaking-change check (first compile, so nothing to compare against — clean)

Stage 2: Dispatches two parallel subagents
  → Backend subagent: /work specs/... --scope backend
    → Reads _generated/ as the API truth
    → Implements the Spring Boot controller + service + repository
    → Adds JUnit tests
    → Runs verification (mvn test, ruff/checkstyle equivalents)
    → Ticks backend acceptance criteria in the spec
  → Frontend subagent: /work specs/... --scope frontend
    → Reads _generated/ as the API truth
    → Implements the Angular component + service + form
    → Adds Karma/Jasmine tests
    → Runs verification (ng test, ng lint)
    → Ticks frontend acceptance criteria in the spec

Stage 3: /check specs/2026-05-12-notif-preferences.md
  → Confirms no drift between spec and code in either scope
  → Reports any criteria ticked without code traces

Stage 4: Reports outcome
  → Files modified per scope, tests added per scope, drift findings
  → Suggests commit messages with §ref to the spec
```

### 3. Review the decisions Claude made

Before merging, surface what Claude chose along the way:

```
/review-decisions specs/2026-05-12-notif-preferences.md
```

You'll see something like:

```
Decision #1
───────────
  Logged: 2026-05-12 14:23 UTC (during /work, scope=backend)
  Decision: Use Spring's @Validated with JSR-303 over manual validation
            in the controller.
  Rationale: Existing controllers in this service all use @Validated;
             matches local convention.

Decision #2
───────────
  Logged: 2026-05-12 14:41 UTC (during /work, scope=backend)
  Decision: Returned 200 with empty body when preferences are unset,
            instead of 404.
  Rationale: Spec was silent; chose 200 because frontend pattern
             elsewhere expects empty-state-as-data, not as error.

Decision #3
───────────
  Logged: 2026-05-12 14:55 UTC (during /work, scope=frontend)
  Decision: Used Angular reactive forms instead of template-driven.
  Rationale: Existing forms in NotificationModule are reactive;
             matching local convention.
```

Mark each verdict. The verdict gets logged to the ledger as a `decision_reviewed` event:

```
accept #1 #3, redo #2 note "must be 404 per OpenAPI conventions, not 200"
```

The `needs-redo` verdict on #2 prompts you to re-run `/work` with the override:

```
/work specs/2026-05-12-notif-preferences.md --scope backend --override "unset preferences must return 404, not 200"
```

### 4. Commit and ship

```bash
# Each scope as a separate commit, both referencing the spec
git add backend/
git commit -m "backend: NOTIF-247 customer notification preferences endpoint

§ref:specs/2026-05-12-notif-preferences.md"

git add frontend/
git commit -m "frontend: NOTIF-247 customer notification preferences UI

§ref:specs/2026-05-12-notif-preferences.md"
```

The pre-commit hook validates spec linkage on each commit. If you forget the `§ref:` or to stage the spec, the hook blocks with a clear message.

### 5. When something breaks in production

Six weeks later, a customer reports notifications stopped working for users with multiple email aliases. Run:

```
/investigate NOTIF-INC-12 email aliases not receiving notifications
```

Claude drafts `investigations/2026-06-23-notif-email-aliases.md` and walks through evidence collection, hypothesis generation, and root cause identification. Once you find it ("the email-uniqueness assumption in the preferences key, established silently in /work, doesn't hold for users with aliases"), status moves to `closed-resolved`.

Run the fix:

```
/fix NOTIF-INC-12 --against specs/2026-05-12-notif-preferences.md --from-investigation investigations/2026-06-23-notif-email-aliases.md
```

This is a **Case 4** (spec was silent on aliases, behaviour emerged in production). The fix creates a superseding spec `specs/2026-06-23-notif-preferences-v2.md` that explicitly handles aliases; the original spec is marked superseded but preserved as historical truth.

After the fix holds for a normal usage cycle:

```
/encode-lesson investigations/2026-06-23-notif-email-aliases.md --fix fixes/2026-06-23-notif-aliases-against-NOTIF-247.md
```

Claude proposes lessons like:

```
Candidate lesson #1:
  Text: "When designing user-keyed APIs, always confirm whether the key
         is unique per identity or per channel; document the assumption
         in the spec's Contract Surface section."
  Type: architectural
  Proposed destination: CLAUDE.md (Non-negotiable invariants section)
```

You approve, Claude inserts the invariant into `CLAUDE.md` with a linkback comment, appends a "Lesson encoded" section to the investigation, and logs a `lesson_encoded` event. Every future `/spec`, `/work`, `/contract`, and `/fix` invocation now reads this invariant on load — the same class of bug can no longer happen the same way again.

### 6. Audit anytime

Two weeks before an internal audit, query the ledger:

```bash
# Every spec shipped in the quarter
python3 .attest/ledger/attest_ledger.py query "
    SELECT artifact_path, started_at, ended_at, outcome
    FROM sessions WHERE command = 'ship'
      AND started_at >= '2026-04-01'
    ORDER BY started_at
"

# Every decision the team reviewed
python3 .attest/ledger/attest_ledger.py query "
    SELECT artifact, summary, review_verdict, reviewer_note, reviewed_at
    FROM decisions WHERE review_verdict IS NOT NULL
"

# Every lesson encoded as a result of an incident
python3 .attest/ledger/attest_ledger.py query "
    SELECT lesson_id, destination_path, source_investigation, ts
    FROM lessons ORDER BY ts DESC
"

# Export to CSV for the auditor's preferred tool
python3 .attest/ledger/attest_ledger.py export-csv sessions-Q2-2026.csv --table sessions

# Or just get a human-readable summary
python3 .attest/ledger/attest_ledger.py summary --since 2026-04-01
```

The answers come from a SQLite database that's been derived from an append-only JSONL log that's been committed to git for the entire period. The audit trail is not separately maintained — it's a byproduct of normal work.

---

## More

- **Workflow diagrams**: see [README.md](./README.md) (in `dist/`, the original workflow doc) for the full set of flow charts
- **Per-command details**: each command's prompt is in `dist/commands/<command>.md` with full discipline rules
- **The ledger**: `dist/ledger/HOW-TO-LOG.md` documents every event type and its fields
- **Bug fix workflow**: `docs/bug-fix-workflow.md` walks the four-case classification with examples
- **Changelog**: [CHANGELOG.md](./CHANGELOG.md) tracks what shipped in each version

## Project status

v0.9.0 — 7 of 11 critiques from the original grilling review closed. 9 commands, 2 skills, observability ledger, contract helpers, pre-commit hook. 68 files total.

License: see [LICENSE](./LICENSE).
