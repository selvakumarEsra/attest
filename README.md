# attest

A standalone workflow for AI-assisted development with [Claude Code](https://docs.claude.com/en/docs/claude-code). Designed for regulated environments (banks, financial services, healthcare) where every code change needs a traceable contract and an auditable trail.

The name reflects what the workflow actually does: every artifact attests to something. A spec attests to intent. A contract attests to the API boundary. A fix attests to a bug and its resolution. A `§ref` comment attests that code traces to a spec. The pre-commit hook attests that nothing slips through without a paper trail. The hash mechanism attests that contracts haven't drifted.

Five things: one constitution per repo, five slash commands, one git hook, one skill. That's the whole system.

## Quick start

```bash
# Clone this repo
git clone https://github.com/<you>/attest.git
cd attest

# Install into your project
./scripts/install.sh /path/to/your/repo

# Open your repo in Claude Code and start with:
#   /spec <your-ticket-id>
```

The installer is idempotent — re-running it is safe. Use `--dry-run` to preview what it would change.

## The workflow at a glance

```
┌─────────────────────────────────────────────────────────────────┐
│  New feature                                                     │
├─────────────────────────────────────────────────────────────────┤
│  /spec → /contract (full-stack only) → /work → git commit       │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Bug fix                                                         │
├─────────────────────────────────────────────────────────────────┤
│  /fix → (optional /contract for spec changes) → /work → commit  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Drift detection (anytime)                                       │
├─────────────────────────────────────────────────────────────────┤
│  /check                                                          │
└─────────────────────────────────────────────────────────────────┘
```

Each command's full behaviour is documented in its own file under `dist/commands/`.

## What's where in this repo

```
attest/
├── README.md                     ← you are here
├── CLAUDE.md                     ← constitution for THIS repo (self-hosted)
├── LICENSE
├── .gitignore
│
├── dist/                         ← source of truth — install into other repos
│   ├── commands/                 ←   the six slash commands
│   ├── hooks/                    ←   pre-commit hook
│   ├── skill/                    ←   two skills
│   └── templates/                ←   CLAUDE.md template
│
├── .claude/                      ← generated copy for self-hosting (sync'd from dist/)
│   ├── commands/
│   └── skills/
│
├── docs/
│   └── bug-fix-workflow.md       ← worked examples of the four bug-fix cases
│
├── examples/                     ← example specs and fixes
│
├── scripts/
│   ├── install.sh                ← install into a target repo
│   ├── sync-local.sh             ← regenerate .claude/ from dist/
│   └── verify-sync.sh            ← CI check: .claude/ matches dist/
│
└── .github/
    ├── workflows/                ← CI
    └── CONTRIBUTING.md
```

## Handling failures (compile errors, runtime errors, broken CI)

Failures take several shapes. The workflow handles each differently:

| Situation | Approach |
|---|---|
| Compile error in code Claude wrote during `/work` | `/work` iterates up to ~3 attempts on the same failure, with different hypotheses each time. After that, it stops and asks the user. Don't disable tests or relax invariants to make failures pass. |
| Compile error in code outside `/work`, trivial (typo, missing import) | Just fix it; commit with `--no-verify` if there's no spec to reference. The audit trail captures bypasses in git log. |
| Runtime error you've observed but don't know the cause of | `/investigate` — captures evidence, hypotheses, what you ruled out, and the root cause once found. Then `/fix --from-investigation` pre-populates the fix with what you learned. |
| Production incident | `/investigate --production` — same flow with the audit bar raised. Combine with your normal incident response process. |
| Broken CI you suspect is environmental (not your code) | `/investigate` and conclude with `closed-external` once you've confirmed. No fix needed; the investigation is the audit trail of "we looked and it wasn't us". |
| Bug you know the cause of immediately | Skip `/investigate`, go straight to `/fix`. The investigation is for unknowns. |

### Why `/investigate` is separate from `/fix`

`/fix` requires a known root cause — it refuses to draft a Resolution without one. That's correct discipline for verified bugs but unworkable for "something just broke and I don't know why yet". `/investigate` is the discovery phase; `/fix` is the resolution phase. Keeping them separate means:

- The investigation has its own append-only log (you don't lose what you tried)
- "Closed without fix" is a valid outcome (not reproducible, was environmental, etc.)
- Multiple people can contribute to one investigation over time
- When a similar failure recurs months later, you can search past investigations for the symptom

In a regulated environment, the investigation record is often more important than the fix itself: it shows you investigated rather than guessed.

## The six commands

| Command | When to use |
|---|---|
| `/spec <ticket>` | New feature, new requirement, or evolution of existing functionality |
| `/contract <spec>` | Compile a spec's Contract surface into `_generated/` artifacts (full-stack only) |
| `/work <spec-or-fix> [--scope]` | Execute against a spec or fix file |
| `/check <spec-or-fix> [--deep]` | Detect drift between a spec/fix and the code |
| `/investigate <ticket>` | Investigate a failure (compile error, runtime error, broken CI, production incident) — produces an investigation file with evidence and root cause |
| `/fix <ticket> --against <spec> [--from-investigation <inv>]` | Bug fix against an existing spec — four-case classification, can chain from `/investigate` |

`/work` accepts either spec or fix files. `/check` is invoked automatically by `/work` and can also be run manually. `/investigate` feeds into `/fix` via the `--from-investigation` flag.

## Adopting attest on an existing codebase

Most adopters have thousands of lines of existing code and no specs. The path:

1. **Install attest** with `./scripts/install.sh /path/to/your/repo`
2. **Write your CLAUDE.md** using the `claude-md-architect` skill (or convert your existing one)
3. **Backfill specs incrementally** using the `spec-reverse-engineer` skill, scoped to one module or endpoint at a time. Bulk reverse-engineering produces unreviewable output.
4. **For new work**, use the standard `/spec → /work` (or `/spec → /contract → /work` for full-stack) loop.
5. **For bugs in already-reverse-engineered code**, use `/fix`. The fix will reference the reverse-engineered spec.

You don't need 100% spec coverage to benefit. The pre-commit hook only enforces spec-linkage on changed `src/` files. If a file hasn't been touched and has no spec, that's fine — it stays as it is. The discipline kicks in when you modify the file.

What does NOT work:

- Bulk auto-generation of specs for the whole codebase in one pass (the output is unreviewable; the skill will warn you)
- Promoting reverse-engineered specs to `draft` without reviewing the `[needs review]` flags (the skill won't do this for you)
- Trying to reverse-engineer pure refactors with no observable behaviour (skip these)

See the `spec-reverse-engineer` skill's reference files for migration rules per source format.

## The skills

Two skills, both user-scoped — installed under `~/.claude/skills/` once, then available in every repo.

### `claude-md-architect`

Writes or converts `CLAUDE.md` files. Four modes:

- **Greenfield** — write a new CLAUDE.md from scratch
- **Conversion** — restructure an existing CLAUDE.md (or AGENTS.md) into the template
- **Audit** — score a CLAUDE.md against the template; surface gaps
- **Hierarchy** — design or refactor nested CLAUDE.md files for monorepos

### `spec-reverse-engineer`

Reverse-engineers attest spec files from material that already exists: source code, existing documentation, OpenAPI definitions, BDD `.feature` files, or specs from other frameworks (Spec Kit, BMAD, Kiro, Tessl). For when you adopt attest on a codebase that already has thousands of files and no specs.

Three scenarios:

- **From code only** — reads source, extracts contract surface from type signatures and routes, extracts acceptance criteria from test assertions
- **From existing docs** — migrates Confluence/Notion/OpenAPI/BDD content into attest's section shape
- **Hybrid** — uses both signals, marks conflicts for human adjudication

Honest about its limits: produces specs with status `draft-reverse-engineered`, marks uncertain sections `[needs review]`, never auto-promotes to `draft`. The user reviews and confirms before the spec is usable with `/work` or `/contract`.

## The Wall (pre-commit hook)

A small bash hook that blocks commits which touch `src/` (or `lib/`, or `app/`) without:

- a `specs/*.md` or `fixes/*.md` file staged in the same commit, OR
- a `§ref:specs/...` or `§ref:fixes/...` reference in the commit message or code

This is the audit gate. Bypassable with `git commit --no-verify` — bypasses are visible in `git log` for after-the-fact review.

Verified against five scenarios in `dist/hooks/`.

## The drift mechanism (key correctness property)

Full-stack work hash-locks the API contract:

1. `/contract` reads a spec's "Contract surface" section, **normalises** it (strips comments, trims whitespace, collapses blank lines), and computes its SHA-256.
2. That hash is stamped into every generated artifact's header (`_generated/openapi/*.yaml`, `_generated/types/*.ts`, etc.).
3. `/work` recomputes the hash and refuses to proceed if it doesn't match the artifacts.

Crucially, the hash is computed over the *Contract surface section only*, not the whole spec file. This means `/contract` can update the spec's metadata (status, contract hash, artifacts list) without breaking the hash equality. The mechanism is verified against three properties:

- Metadata edits don't change the hash ✓
- Real contract edits DO change the hash ✓
- Cosmetic whitespace changes don't change the hash ✓

A reference Python implementation lives at `dist/commands/contract_hash.py`. Test fixtures under `dist/commands/test-fixtures/`.

## Why this design, and what it isn't

The workflow was sparked by the Two-Commander model from a blog post arguing for two human roles managing an agent fleet. The model is rhetorical — what it actually describes is *artifact-centric authority*: the spec carries the contract, the fix carries the bug context, the generated artifacts carry the API boundary, and the commit history carries the audit trail. Tools enforce the boundaries; one human (or several wearing different hats) drives the artifacts through stages.

`attest` is the minimum viable implementation of that idea. It deliberately omits:

- The "two-commander org chart" rhetoric (the human roles aren't the architecture)
- Agent personas (Claude Code's built-in subagents handle that)
- An elaborate framework with 20+ commands

If you need any of those, fork and extend. The README in `dist/commands/` describes when to add each piece and what trigger justifies it.

## Working on this repo itself

This repo eats its own dog food: it uses its own commands and skill to develop itself.

```bash
# After editing files under dist/, sync them into .claude/ for local use
./scripts/sync-local.sh

# Then in Claude Code, you can use /spec, /contract, /work etc. on this repo
```

CI verifies the sync via `./scripts/verify-sync.sh`. PRs that change `dist/` but not `.claude/` will fail.

## Project status

- v6 — current. Full feature set: four work commands, bug-fix workflow, nested CLAUDE.md, hash-locked contracts.
- Active maintenance, but not yet 1.0. Breaking changes possible at the command-prompt level until 1.0.

## Contributing

See `.github/CONTRIBUTING.md`. The short version: edit `dist/`, run `./scripts/sync-local.sh`, commit both, open a PR. CI will reject PRs that break the sync invariant.

## License

MIT. See `LICENSE`.
