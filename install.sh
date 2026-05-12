#!/usr/bin/env bash
#
# install.sh — install the attest workflow into a target repo
#
# Usage:
#   ./scripts/install.sh <path-to-target-repo>
#   ./scripts/install.sh <path-to-target-repo> --skip-skill   # don't install user-scoped skill
#   ./scripts/install.sh <path-to-target-repo> --user-commands # install commands to ~/.claude instead of project
#
# What this script does:
#   1. Drops CLAUDE.md template at the target repo root (only if no CLAUDE.md exists)
#   2. Creates specs/, fixes/, _generated/ directories
#   3. Installs slash commands under <target>/.claude/commands/
#   4. Installs the pre-commit hook into <target>/.git/hooks/pre-commit
#   5. Installs the claude-md-architect skill under ~/.claude/skills/ (user-scoped)
#
# This script is idempotent — re-running it is safe; existing files are
# preserved (with .bak backup) rather than overwritten.

set -euo pipefail

# ---- Argument parsing ----

if [[ $# -lt 1 ]]; then
    cat >&2 <<EOF
Usage: $0 <path-to-target-repo> [options]

Options:
  --skip-skill        Skip installing the claude-md-architect skill
  --user-commands     Install slash commands to ~/.claude (user-scoped)
                      instead of <target>/.claude (project-scoped)
  --skip-hook         Skip installing the pre-commit hook
  --dry-run           Print what would be done; make no changes
EOF
    exit 2
fi

TARGET="$1"; shift
SKIP_SKILL=0
USER_COMMANDS=0
SKIP_HOOK=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-skill) SKIP_SKILL=1 ;;
        --user-commands) USER_COMMANDS=1 ;;
        --skip-hook) SKIP_HOOK=1 ;;
        --dry-run) DRY_RUN=1 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# ---- Validate target ----

if [[ ! -d "$TARGET" ]]; then
    echo "Target directory does not exist: $TARGET" >&2
    exit 1
fi

if [[ ! -d "$TARGET/.git" ]]; then
    echo "Target is not a git repository: $TARGET" >&2
    echo "Run 'git init' there first, or point install.sh at a real repo." >&2
    exit 1
fi

# Resolve absolute paths
TARGET=$(cd "$TARGET" && pwd)
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIST="$REPO_ROOT/dist"

if [[ ! -d "$DIST" ]]; then
    echo "Cannot find dist/ at $DIST" >&2
    echo "Are you running install.sh from a clone of attest?" >&2
    exit 1
fi

# ---- Helpers ----

run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "DRY: $*"
    else
        eval "$@"
    fi
}

# Copy a file, backing up the destination if it already exists with different content
safe_copy() {
    local src="$1" dest="$2"
    if [[ -f "$dest" ]]; then
        if cmp -s "$src" "$dest"; then
            echo "  unchanged: $dest"
            return
        fi
        local backup="${dest}.bak.$(date +%Y%m%d-%H%M%S)"
        echo "  backing up existing → $backup"
        run "cp '$dest' '$backup'"
    fi
    run "cp '$src' '$dest'"
    echo "  installed: $dest"
}

# ---- Install steps ----

echo "Installing attest workflow into: $TARGET"
[[ $DRY_RUN -eq 1 ]] && echo "(dry run — no files will be changed)"
echo ""

# 1. CLAUDE.md template (only if no CLAUDE.md exists)
echo "1/5  CLAUDE.md template"
if [[ -f "$TARGET/CLAUDE.md" ]]; then
    echo "  CLAUDE.md already exists — leaving untouched."
    echo "  To convert it to the attest template, run the claude-md-architect skill in Claude Code."
else
    run "cp '$DIST/templates/CLAUDE.md.template' '$TARGET/CLAUDE.md'"
    echo "  installed: $TARGET/CLAUDE.md (fill in the placeholders)"
fi
echo ""

# 2. Directories
echo "2/5  Directories"
for dir in specs fixes _generated; do
    if [[ -d "$TARGET/$dir" ]]; then
        echo "  exists: $TARGET/$dir/"
    else
        run "mkdir -p '$TARGET/$dir'"
        echo "  created: $TARGET/$dir/"
    fi
done
# .gitattributes for _generated
if [[ ! -f "$TARGET/_generated/.gitattributes" ]]; then
    run "echo '* linguist-generated=true' > '$TARGET/_generated/.gitattributes'"
    echo "  installed: $TARGET/_generated/.gitattributes"
fi
echo ""

# 3. Slash commands
if [[ $USER_COMMANDS -eq 1 ]]; then
    CMD_DEST="$HOME/.claude/commands"
    echo "3/5  Slash commands (user-scoped → $CMD_DEST)"
else
    CMD_DEST="$TARGET/.claude/commands"
    echo "3/5  Slash commands (project-scoped → $CMD_DEST)"
fi
run "mkdir -p '$CMD_DEST'"
for cmd in spec contract work check fix; do
    safe_copy "$DIST/commands/${cmd}.md" "$CMD_DEST/${cmd}.md"
done
echo ""

# 4. Pre-commit hook
if [[ $SKIP_HOOK -eq 1 ]]; then
    echo "4/5  Pre-commit hook (skipped via --skip-hook)"
else
    echo "4/5  Pre-commit hook"
    safe_copy "$DIST/hooks/pre-commit" "$TARGET/.git/hooks/pre-commit"
    run "chmod +x '$TARGET/.git/hooks/pre-commit'"
fi
echo ""

# 5. Skill (user-scoped)
if [[ $SKIP_SKILL -eq 1 ]]; then
    echo "5/5  claude-md-architect skill (skipped via --skip-skill)"
else
    SKILL_DEST="$HOME/.claude/skills/claude-md-architect"
    echo "5/5  claude-md-architect skill (user-scoped → $SKILL_DEST)"
    run "mkdir -p '$SKILL_DEST/references'"
    safe_copy "$DIST/skill/claude-md-architect/SKILL.md" "$SKILL_DEST/SKILL.md"
    for ref in template nested-template conversion-rules examples hierarchy-examples; do
        safe_copy "$DIST/skill/claude-md-architect/references/${ref}.md" "$SKILL_DEST/references/${ref}.md"
    done
fi
echo ""

# ---- Done ----

cat <<EOF
Done.

Next steps:
  1. Open $TARGET/CLAUDE.md and fill in the placeholders (Project type,
     Backend language, Frontend language, Contract pair name, invariants).
  2. In Claude Code, run /spec on your next ticket to start the workflow.
  3. Read $REPO_ROOT/README.md for the full daily loop.

If anything looks wrong, re-run with --dry-run to see what would happen
without making changes.
EOF
