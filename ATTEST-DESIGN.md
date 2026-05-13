# attest — design archive

> **Audience**: anyone — Claude or human — who needs to understand *why* attest
> is the way it is, not just *how* to use it. This is the document you read
> before changing attest itself, or before making architectural decisions
> about how attest is adopted at scale.
>
> **What this is NOT**: not a user manual (see `README.md`), not a release log
> (see `CHANGELOG.md`), not a maintenance guide for the repo itself (see
> `CLAUDE.md`). This is the *design archive*.

## 1. What attest is, in one paragraph

A spec-driven development workflow for Claude Code, built for tier-1 bank
engineering under MAS AIRG / SR 11-7-equivalent regulatory regimes. Specs,
fixes, and investigations are first-class artifacts that drive both Claude
and humans through the same pipeline. A pre-commit hook ("the Wall") refuses
production code without artifact linkage. An observability ledger (JSONL +
SQLite) records every command, decision, drift finding, and gate event
into an append-only audit trail. The result: the audit trail is a byproduct
of normal work, not a separate compliance burden.

## 2. The originating context

attest was built by **Selva**, a Solution Architect at a tier-1 Singapore
bank, working on SGEN/NCBS batch pipelines in a MAS AIRG-regulated
environment. The use case is **developing full-stack applications inside
the bank** where every line of code must survive examination questions like:

- "How did this change get from a business requirement to production?"
- "What did your AI assistant decide that a human didn't explicitly tell it
  to decide?"
- "When the spec and the code disagreed, which one did your team trust?"
- "Show me your AI-usage inventory for Q3."
- "Did the team learn from incident X, and where is that lesson encoded so
  it can't happen the same way again?"

The earlier-arc context includes deep work on Spec-Driven Development (SDD)
generally: evaluating Kiro, Tessl, Speckit, BMAD, ThoughtWorks/Fowler's
critique; building multi-stakeholder SDD framework designs and executive
presentation decks. attest is the **standalone, opinionated successor**
to an earlier `sdd-workflow` skill (8 commands) — explicitly NOT extending
it, deliberately starting fresh.

The framework deliberately optimizes against startup-tempo defaults. Most
AI-assisted dev workflows minimize keystrokes between idea and shipped
code. In a bank, that optimization runs backward — the audit trail IS the
value, and shortcuts that erase it are unacceptable.

## 3. The architectural decisions, with rejected alternatives

Each decision below was made deliberately. Future changes that violate these
should require explicit re-decision, not drift.

### 3.1 Artifact-centric, not role-centric

**Decision**: Specs, fixes, investigations, and contract artifacts are the
primary entities. Each carries its own traceability.

**Rejected**: Role-centric design (PM, Architect, Developer, Tester agents)
as seen in BMAD and similar frameworks. Roles produce ceremony; artifacts
produce evidence.

**Why**: An auditor's question is "show me the artifact" — never "show me
which role decided." Artifacts are queryable, roles are not.

### 3.2 Hash-locked contracts

**Decision**: SHA-256 over the normalised Contract Surface section of a
spec, stamped into every generated artifact's header. `/work` recomputes
and refuses to proceed on mismatch.

**Reference implementation**: `dist/commands/contract_hash.py`. Tested via
`dist/commands/test-fixtures/spec-before.md` and `spec-after.md` — the hash
is stable across `/contract`-induced metadata edits but sensitive to real
contract edits.

**Rejected**:
- Hash over the entire spec → fragile to any cosmetic edit
- Timestamp-based versioning → not deterministic, not verifiable
- Git blob hashes → opaque to humans, can't survive cherry-picks

### 3.3 JSONL source of truth, SQLite derived index

**Decision**: The ledger has two storage layers. `.attest/ledger/events.jsonl`
is **the** source of truth — append-only, committed to git, human-readable.
`.attest/ledger/index.db` is a **derived** SQLite projection — gitignored,
rebuildable at any time via `rebuild-index`.

**Rejected**:
- JSONL only → no SQL queries, no joins across event types, awkward for reports
- SQLite only → binary format that's hostile to git, locking under
  concurrency, recovery from corruption is hard
- Postgres / external store → introduces operational dependency that defeats
  the "drop-in, no services" property

**Why**: It mirrors how production observability stacks work (Kafka durable
+ Postgres/ClickHouse index) but at single-repo scale with no operational
overhead. Verified concurrent-safe at 20 parallel writers via the
O_APPEND-at-PIPE_BUF atomicity property of POSIX append-only writes.

### 3.4 The Wall as a soft gate

**Decision**: The pre-commit hook refuses commits without artifact linkage,
but is bypassable via `git commit --no-verify`. Bypasses are logged
separately as `gate_bypassed` events.

**Six acceptance scenarios**: (1) only docs/specs/fixes/investigations
staged, (2) src + spec staged, (3) src + fix staged, (4) src + investigation
staged, (5) src with `§ref:` comment in code, (6) `--no-verify` deliberate
bypass.

**Rejected**:
- Hard gate (no bypass) → blocks emergency hotfixes in genuine incidents;
  inconsistency between gate behaviour creates worse audit risk than the
  bypass itself
- Server-side enforcement only → server-side checks happen too late; local
  gate catches problems before they enter shared history
- Per-author whitelist → ceremony for no audit value

**Why bypasses matter**: The Wall's job is to make the audit-trail gap
*noisy*. Bypasses ARE the audit-relevant event when they happen — the
ledger records the bypass with full context, and reviewers can ask why.

### 3.5 `/ship` orchestrator with parallel subagents

**Decision**: For full-stack work, `/ship` is the single user-visible
command. Internally it runs `/contract` (Stage 1), then dispatches two
Task subagents in parallel for backend and frontend `/work` (Stage 2),
then runs `/check` (Stage 3), then reports (Stage 4).

**Rejected**:
- User runs `/contract` then `/work` then `/work` then `/check` manually
  — works but is 4 sessions of friction
- Single `/work` with both scopes → loses the scope-locked discipline,
  encourages cross-scope leakage
- More than 2 subagents → coordination overhead grows faster than
  parallelism gain for typical full-stack work

**Critical pattern in `/ship` prompt**: "issue both Task invocations in the
same response." Claude Code dispatches Task calls in parallel when issued
in one response, sequentially otherwise. This is fragile — if the prompt
is paraphrased and loses that phrase, parallelism breaks silently.

### 3.6 Bug-fix four-case classification

**Decision**: `/fix` requires explicit classification on entry. Case 1
(code wrong, spec right) modifies only code. Case 2 (spec wrong) creates
a superseding spec; original preserved as `superseded`. Case 3 (requirement
evolved) refuses and redirects to `/spec`. Case 4 (spec silent) creates
a superseding spec like Case 2.

**Rejected**:
- Single "fix" model that always modifies the spec → erases audit-relevant
  fact that the system once promised X before changing to Y
- Single "fix" model that never modifies the spec → can't capture cases
  where the spec itself was wrong
- Hierarchy of bug severities → not what regulators ask about; the
  case-classification is the audit-relevant axis

**Why originals are preserved**: "What did this system promise at time T?"
is an answerable question only if the spec from time T still exists in git.

### 3.7 Investigation separate from fix

**Decision**: `/investigate` and `/fix` are distinct commands with distinct
artifacts. Investigation = discovery phase; fix = resolution phase.

**Four terminal investigation statuses**: `closed-resolved` (chains to fix),
`closed-not-reproducible`, `closed-external`, `stalled`.

**Rejected**: Combined "incident" command that does both. Conflates two
audit trails — "what we tried" lives in the investigation, "what we did"
lives in the fix. Mixing them poisons the audit trail.

### 3.8 The learning loop closure

**Decision**: After a fix from a `closed-resolved` investigation holds for
a normal usage cycle, `/encode-lesson` promotes a lesson from the
investigation into a durable invariant in CLAUDE.md (or nested CLAUDE.md,
skill gotcha, or command prompt).

**Hard rules in `/encode-lesson`** that future changes should preserve:
- Refuses motherhood statements ("write good tests")
- Refuses lessons from unresolved investigations
- Refuses duplicates of existing invariants
- Caps at 3 lessons per investigation (5 lessons would signal a culture
  issue, not 5 invariants)
- Refuses to bloat CLAUDE.md past 200 lines

**Stable lesson_id**: hash of the lesson text, embedded in both the
destination artifact's linkback comment AND the ledger entry. Audit
trail can query "every lesson encoded, where it lives, which investigation
it came from" via the `lessons` table.

### 3.9 Decision review with soft-reject

**Decision**: `/work` logs `decision_logged` events for non-obvious choices.
`/review-decisions` surfaces them; human marks verdict as `accepted`,
`rejected`, or `needs-redo`. Original log is append-only; verdicts layer
on top as `decision_reviewed` events.

**Three verdicts, deliberate distinctions**:
- `accepted` — agreed; recorded
- `rejected` — disagreed; cost of redoing exceeds cost of accepting; code
  stands, trail records disagreement
- `needs-redo` — must be fixed before merge; user re-runs `/work` with
  override

**Rejected**: auto-redo on `needs-redo`. Sometimes "needs-redo" means
"please re-do this thoughtfully with my correction" — automatic re-run
would lose the override context. The human re-runs deliberately.

### 3.10 Model-version pinning, advisory not enforced

**Decision**: Every command's frontmatter has a `recommended-model` field
(sonnet or opus). The ledger captures the model actually used per session.
Divergence is queryable but not blocked.

**Per-command split**:
- sonnet: spec, contract, check, review-decisions (textual + judgment)
- opus: work, ship, fix, investigate, encode-lesson (heavy execution,
  hypothesis generation, high-stakes abstraction)

**Rejected**:
- Hard enforcement → Claude Code uses whatever model the user selected;
  attest can't override
- Model-regression eval suite → premature; right time to add evals is
  after empirical signal from real ticket use surfaces which commands
  are most model-sensitive

### 3.11 Structural breaking-change detection

**Decision**: When `/contract` re-runs and the hash differs, run a
structural diff against the previous OpenAPI artifact. Classify changes
as additive or breaking. Surface to user for explicit confirmation.

**Tool selection**: Uses `oasdiff` if installed (gold-standard). Falls
back to built-in Python detector that catches removed endpoints, type
changes, new required fields, removed enum values, removed response
codes, required-parameter additions.

**Rejected**:
- Hard dependency on `oasdiff` → real friction in regulated install
  environments; Go binary installation is non-trivial
- Hard block on breaking changes → sometimes breaking changes are
  intentional (deliberate API version bump); classification is the
  audit-relevant fact, not enforcement
- Python-only → loses the precision of oasdiff for complex OpenAPI
  features ($ref chains, allOf composition, etc.)

### 3.12 Coverage gating via three-gate pipeline

**Decision** (v0.10.0): Test coverage is enforced as a three-gate pipeline.
`/work` post-flight Step 3.5 measures, refuses status promotion if delta
below threshold. Pre-commit hook reads the most recent `coverage_measured`
event, blocks if failing (bypassable). CI is the authoritative re-measurement.

**Gating metric**: **Delta coverage** (lines added/modified in this session
that are covered by tests), not project coverage. Project coverage tracked
alongside as informational.

**Rejected**:
- Project coverage as gate → answers "is the codebase well-tested" but not
  the AI-relevant question "did Claude properly test what Claude added"
- attest implementing its own coverage tool → would be a multi-language
  tarpit; instead attest delegates to the team's existing tool (pytest,
  jest, go test, etc.) and parses the output
- Auto-generating tests when coverage is low → tests-that-exist-purely-to-
  lift-a-number poison the audit trail
- Hook re-runs coverage tool → makes commits painfully slow; instead the
  hook reads the most recent measurement from the ledger

**Critical implementation note**: The hook MUST run `rebuild-index` before
querying the coverage table, because the JSONL is the source of truth and
the SQLite index can be stale (`/work` writes to JSONL, doesn't auto-rebuild
index; rebuild is fast — under 200ms — but missing it means the hook reads
yesterday's coverage). This added ~200ms per commit in repos with active
coverage policies.

## 4. The version progression

| Version | Closed critique | Net new |
|---------|-----------------|---------|
| v0.6.x  | (pre-grilling baseline) | spec/contract/work/check/fix/investigate commands, the Wall, two skills |
| v0.7.0  | #1 (no observability) + #2 (no orchestrator) | JSONL+SQLite ledger, `/ship` |
| v0.8.0  | #5 (no learning loop) + #6 (no structural diff) | `/encode-lesson`, breaking-change detection |
| v0.9.0  | #4 (no decision review) + #10 (no model pinning) + #11 (no scope statement) | `/review-decisions`, frontmatter, README scope table |
| v0.10.0 | (coverage — out-of-band requirement from bank ticket use) | coverage gate, `coverage_measured` event, coverage table |

**Closed**: 8 of 11 grilling critiques + 1 out-of-band (coverage).

**Open**:
- #3 (server-side CI templates) — high compliance value, on critical path for scale
- #7 (formal `/post-mortem` command) — close cousin of `/encode-lesson`,
  not yet needed
- #8 (framework starter mode for new teams) — adoption-friction concern,
  not yet bottleneck
- #9 (reverse-engineer bulk mode + confidence scoring) — for onboarding
  existing codebases at scale

**Recommendation pattern across versions**: stop adding, start using. The
meta-lesson from the grilling document. v0.10.0 was the first addition
driven by **real ticket signal** (the bank's 90% coverage requirement)
rather than speculation about what attest should do. Future additions
should follow the same pattern: real friction first, then change.

## 5. The grilling document, in summary

A 426-line comparative review at `/mnt/user-data/outputs/attest-grilling.md`
(if still present in your environment) benchmarked attest against:

- **Anthropic engineering** practices for Claude Code workflows
- **Stripe, Ramp, Wiz, Rakuten** AI-engineering case studies (especially
  Stripe's 10K-line migration in 4 days, Wiz's 50K-line library in 20 hours)
- **Goldman Sachs, JPMorgan** public statements on AI engineering governance
- **MAS AIRG** (November 2025 consultation, March 2026 Project MindForge
  toolkit, 12-month transition window)
- **LangSmith, Arize Phoenix** observability landscape
- **Drew Breunig's SDD Triangle** framing of spec-driven development

The 11 critiques and their status (as of v0.10.0):

1. ✅ No observability / ledger
2. ✅ No subagent / multi-agent orchestration
3. ⏳ Pre-commit hook is local-only; server-side gates missing
4. ✅ No human-in-loop decision log
5. ✅ No closure loop investigation → CLAUDE.md
6. ✅ Hash mechanism without structural diff
7. ⏳ No formal `/post-mortem` command
8. ⏳ Framework bloat — needs starter mode for new teams
9. ⏳ Reverse-engineering needs bulk mode + confidence scoring
10. ✅ No model-version pinning
11. ✅ No "what attest is NOT" scope statement

## 6. The full file inventory (v0.10.0)

70 files total. Key locations:

```
attest/
├── README.md                                       ← user manual (397 lines)
├── CLAUDE.md                                       ← maintenance guide for this repo
├── CHANGELOG.md                                    ← release log (236 lines)
├── ATTEST-DESIGN.md                                ← THIS FILE — design archive
├── LICENSE
├── .gitignore                                      ← incl. .attest/ledger/index.db
│
├── dist/                                           ← INSTALLABLE SOURCE OF TRUTH
│   ├── commands/                                       ← 9 slash commands
│   │   ├── spec.md, contract.md, work.md, ship.md,
│   │   ├── check.md, fix.md, investigate.md,
│   │   ├── encode-lesson.md, review-decisions.md
│   │   ├── contract_hash.py                            ← reference hash implementation
│   │   ├── test-fixtures/spec-before.md, spec-after.md ← hash stability fixtures
│   │   └── README.md
│   │
│   ├── hooks/pre-commit                                ← The Wall + coverage gate
│   │
│   ├── ledger/
│   │   ├── attest_ledger.py                            ← Python CLI: log, rebuild-index, query, summary, export-csv
│   │   ├── ledger.sh                                   ← bash helpers (attest_log, etc.)
│   │   └── HOW-TO-LOG.md                               ← central reference for command-specific logging patterns
│   │
│   ├── contract/
│   │   ├── breaking-change-check.sh                    ← bash wrapper, oasdiff-first
│   │   └── breaking-change-fallback.py                 ← Python fallback when oasdiff absent
│   │
│   ├── coverage/
│   │   └── coverage-check.py                           ← coverage measurement + delta vs project
│   │
│   ├── skill/
│   │   ├── claude-md-architect/                        ← 4 modes incl. nested CLAUDE.md
│   │   └── spec-reverse-engineer/                      ← code/docs → spec migration
│   │
│   └── templates/
│       └── CLAUDE.md.template                          ← target-repo CLAUDE.md template
│
├── .claude/                                        ← generated copy, synced from dist/
│   ├── commands/, ledger/, contract/, coverage/, skills/
│   └── (verify-sync.sh checks this matches dist/)
│
├── docs/
│   └── bug-fix-workflow.md                             ← four-case classifier deep dive
│
├── examples/
│   └── example-spec-notif-prefs.md                     ← worked example
│
├── scripts/
│   ├── install.sh                                      ← 8-step idempotent installer
│   ├── sync-local.sh                                   ← dist/ → .claude/ projection
│   └── verify-sync.sh                                  ← CI check that .claude matches dist
│
└── .github/
    ├── workflows/ci.yml                                ← 15+ test jobs
    ├── CONTRIBUTING.md
    └── ISSUE_TEMPLATE/
```

## 7. Ledger event types & schema (v0.10.0)

16 known event types, 7 SQLite tables. The JSONL captures everything;
the SQLite indexer projects to specialised tables for fast queries.

**Event types**:
- `session_start` / `session_end` — command invocation lifecycle
- `artifact_created` / `artifact_updated` — spec/fix/investigation/contract changes
- `decision_logged` — Claude made a non-obvious choice in `/work`
- `decision_reviewed` — human assigned a verdict via `/review-decisions`
- `drift_detected` — `/check` found drift
- `gate_passed` / `gate_blocked` / `gate_bypassed` — pre-commit hook outcomes
- `subagent_spawned` / `subagent_completed` — `/ship` orchestration
- `verification_ran` — test/lint command outcome
- `lesson_encoded` — invariant added via `/encode-lesson`
- `breaking_change_detected` — `/contract` structural diff result
- `coverage_measured` — coverage gate result (v0.10.0)

**SQLite tables**:
- `events` — generic event log (all event types)
- `sessions` — projected from session_start/session_end
- `artifacts` — projected from artifact_created/artifact_updated
- `decisions` — projected from decision_logged + decision_reviewed (UPSERT
  on decision_id)
- `lessons` — projected from lesson_encoded
- `breaking_changes` — projected from breaking_change_detected
- `coverage` — projected from coverage_measured (v0.10.0)

**Critical pattern**: The indexer uses `INSERT OR REPLACE` on most tables;
for `decisions` table specifically it uses `INSERT…ON CONFLICT(decision_id)
DO UPDATE` so that `decision_reviewed` events layer verdicts onto rows
created by earlier `decision_logged` events.

## 8. Known traps for future modifications

### 8.1 SQL string literals in shell-quoted queries

**Trap**: SQLite treats double-quoted identifiers as column names with
silent fallback to string literal. If you write `WHERE col="accepted"` in
shell-quoted SQL, and a column named `accepted` exists in the same table,
SQLite silently uses the column instead of the string literal, returning
zero rows.

**Hit**: tested an early v0.9.0 build, got 0/1/1 for accepted/rejected/needs-redo.
Spent time on a non-existent bug because the test was wrong.

**Rule**: Always use **single quotes** for SQL string literals inside
shell scripts. Reserve double quotes for shell variable expansion.

### 8.2 Pre-commit hook reading stale SQLite

**Trap**: The hook queries `index.db` for the most recent `coverage_measured`
event. But the JSONL is the source of truth; the SQLite index only
updates on `rebuild-index`. `/work` writes to JSONL but doesn't auto-rebuild.
If the hook queries without rebuilding first, it sees yesterday's data.

**Rule**: Any time you add a hook-side check that reads the ledger, the
hook MUST call `rebuild-index` first. The cost is ~200ms; the alternative
is silently wrong gates.

### 8.3 `/ship` Task dispatch must be parallel

**Trap**: Claude Code runs Task tool invocations in parallel only when
issued in the same response. If they're issued sequentially (across
multiple responses), they execute sequentially. The `/ship` prompt
specifically says "issue both Task invocations in the same response" —
paraphrasing this away breaks the parallelism silently.

**Rule**: If editing `/ship` prompt, preserve the explicit "same response"
phrasing. Don't smooth it out.

### 8.4 The `.attest/` directory is not the same as `.claude/`

**Trap**: `.claude/` is for Claude Code (commands, skills). `.attest/`
is for attest runtime (ledger, coverage helpers, contract helpers).
They're separate by design — Claude Code skills are user-scoped or
project-scoped via Claude Code's conventions; attest runtime files are
project-scoped via attest's conventions.

**Why this matters**: Future changes that conflate them (e.g., putting
ledger inside `.claude/`) break the install/sync model.

### 8.5 events.jsonl is committed; index.db is not

**Trap**: Forgetting to add `.attest/ledger/index.db*` to .gitignore on
install means the SQLite (binary, rebuildable, often noisy on every
rebuild) ends up in commits.

**Rule**: install.sh handles this on first install but only for new
repos. If installing into a repo that already has a `.gitignore`, the
script appends the entries — verify after install.

### 8.6 Coverage policy detection is by-section-heading

**Trap**: The hook and coverage helper detect "is coverage gating active?"
by looking for `^##\s+Coverage policy` in CLAUDE.md. If a future contributor
renames the section (e.g. to "Test coverage") without updating the detection
in both the hook AND the helper, gating silently disables.

**Rule**: Section heading is API surface. If you change it, change all
three places: template, hook, helper.

## 9. The honest stop-recommendation

The grilling document warned, twice across the version progression, against
adding faster than empirical signal can validate. At v0.10.0, the framework
is **70 files, 9 commands, observability ledger, contract integrity layer,
learning loop, decision review, coverage gate, two skills, pre-commit hook,
CI workflow, multiple diagrams, comprehensive README**.

That is enough surface area to deploy and learn from. Of the four remaining
critiques (#3, #7, #8, #9), only **#3 (server-side CI templates)** has high
enough compliance value to justify being pulled forward without empirical
signal. The other three should wait for real ticket friction.

**The right pattern for v0.11.0 and beyond**: use attest on a real bank
ticket for at least 2-3 cycles. Notice where the friction is. Bring back
*that specific friction* as the trigger for the next change. Do not
add speculatively.

## 10. Pointers to other artifacts

- **`README.md`** — user manual, target audience: developers adopting attest
- **`CLAUDE.md`** — maintenance guide for the attest repo itself
- **`CHANGELOG.md`** — release log, version-by-version
- **`docs/bug-fix-workflow.md`** — four-case classifier deep dive
- **`examples/example-spec-notif-prefs.md`** — worked example spec
- **`dist/ledger/HOW-TO-LOG.md`** — per-command logging patterns reference
- **The grilling document** (`/mnt/user-data/outputs/attest-grilling.md` if
  present) — comparative industry review

## 11. Workflow context

The user (Selva) has these adjacent ongoing concerns that may surface in
future sessions about attest:

- **Local LLM infrastructure** on Mac Studio M4 Max — evaluating Qwen 3.x
  MoE variants, MLX vs LM Studio, Ollama, OpenRouter vs Claude Direct
- **NanoClaw-based trading agents** with Hermes, agentic workflows for
  trading
- **Earlier `sdd-workflow` skill** with 8 commands — explicitly NOT extended
  by attest, deliberately separate
- **`glgen-ncbs` / `sgen-batch-services` project** — the bank's actual
  codebase where attest is being adopted
- **Agentic AI governance** evaluation against MAS AIRG requirements —
  attest is one component, not the whole program

When a future session refers to "the project" without qualifying, it's
almost certainly attest. When it refers to "the bank work" or "the ticket",
it's the glgen-ncbs work that uses attest. The two are intentionally
separate scopes.

---

*This file is intentionally outside `dist/` so it doesn't get installed
into target repos. It's metadata about attest, for attest's own
maintenance.*
