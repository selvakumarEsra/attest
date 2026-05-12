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
│   ├── commands/                 ←   the five slash commands
│   ├── hooks/                    ←   pre-commit hook
│   ├── skill/                    ←   claude-md-architect skill
│   └── templates/                ←   CLAUDE.md template
│
├── .claude/                      ← generated copy for self-hosting (sync'd from dist/)
│   ├── commands/
│   └── skills/
│
├── docs/
│   └── bug-fix-workflow.md       ← worked examples of the four bug-fix cases
│
├── examples/                     ← example specs and fixes (coming)
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

## The five commands

| Command | When to use |
|---|---|
| `/spec <ticket>` | New feature, new requirement, or evolution of existing functionality |
| `/contract <spec>` | Compile a spec's Contract surface into `_generated/` artifacts (full-stack only) |
| `/work <spec-or-fix> [--scope]` | Execute against a spec or fix file |
| `/check <spec-or-fix> [--deep]` | Detect drift between a spec/fix and the code |
| `/fix <ticket> --against <spec>` | Bug fix against an existing spec — four-case classification |

`/work` accepts either spec or fix files. `/check` is invoked automatically by `/work` and can also be run manually.

## The skill

`claude-md-architect` writes or converts `CLAUDE.md` files. Four modes:

- **Greenfield** — write a new CLAUDE.md from scratch
- **Conversion** — restructure an existing CLAUDE.md (or AGENTS.md) into the template
- **Audit** — score a CLAUDE.md against the template; surface gaps
- **Hierarchy** — design or refactor nested CLAUDE.md files for monorepos

The skill is user-scoped — installed under `~/.claude/skills/` once, then available in every repo.

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
