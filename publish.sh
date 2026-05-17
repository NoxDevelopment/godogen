#!/usr/bin/env bash
# Publish godogen skills into a target project directory.
# Creates .claude/skills/ and copies a CLAUDE.md.
#
# Usage: ./publish.sh <target_dir> [claude_md]
#   claude_md  Path to CLAUDE.md to use (default: teleforge.md)
#
# Sync strategy: each godogen skill is rsync'd into the consumer's
# .claude/skills/<skill>/ with --delete scoped to that single subdir.
# Sibling-repo skills installed alongside (godot-ui, godotsmith, etc.) and
# project-local override dirs (godot-ui-overrides/, *.local/) are left
# untouched. Skills *removed* from godogen do NOT auto-delete from the
# consumer — print a notice listing orphans so the operator can clean up.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <target_dir> [claude_md]"
    exit 1
fi

TARGET="$(cd "$1" 2>/dev/null && pwd || (mkdir -p "$1" && cd "$1" && pwd))"
CLAUDE_MD="${2:-$REPO_ROOT/teleforge.md}"

echo "Publishing godogen skills to: $TARGET"

mkdir -p "$TARGET/.claude/skills"

# Per-skill sync: copy each godogen skill subdir with --delete scoped to it.
# This means modifications within a managed skill get blown away (correct —
# users shouldn't edit published skills) but unrelated skills in the consumer
# (e.g. godot-ui, godotsmith) survive.
#
# Uses rsync when available; falls back to rm -rf + cp -r on platforms without
# rsync (Windows Git Bash, etc). Excludes are honored only in the rsync path;
# the fallback removes any doc_source/ + __pycache__/ from the destination
# after the copy.
godogen_skills=()
have_rsync=true
command -v rsync >/dev/null 2>&1 || have_rsync=false

for src in "$REPO_ROOT"/skills/*/; do
    name="$(basename "$src")"
    godogen_skills+=("$name")
    dest="$TARGET/.claude/skills/$name"
    if $have_rsync; then
        mkdir -p "$dest"
        rsync -a --delete --exclude='doc_source/' --exclude='__pycache__/' \
            "$src" "$dest/"
    else
        rm -rf "$dest"
        cp -r "$src" "$dest"
        # Strip exclusions post-copy
        rm -rf "$dest/doc_source"
        find "$dest" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
    fi
done
echo "Published ${#godogen_skills[@]} godogen skills: ${godogen_skills[*]}"
$have_rsync || echo "(fallback used: rm -rf + cp -r; rsync not available)"

# Identify orphans — anything in the consumer's .claude/skills/ that:
#  - isn't a godogen skill we just published
#  - isn't a known sibling-repo skill or local override pattern
sibling_known=(godot-ui godot-ui-overrides godotsmith ui-ux-pro-max gamegen unitygen unity-task unrealgen unreal-task)
orphans=()
shopt -s nullglob
for d in "$TARGET"/.claude/skills/*/; do
    n="$(basename "$d")"
    if printf '%s\n' "${godogen_skills[@]}" | grep -qx -- "$n"; then continue; fi
    if printf '%s\n' "${sibling_known[@]}" | grep -qx -- "$n"; then continue; fi
    # Heuristic: anything ending in -overrides or .local is a project-local override
    case "$n" in
        *-overrides|*.local) continue ;;
    esac
    orphans+=("$n")
done
shopt -u nullglob
if [ "${#orphans[@]}" -gt 0 ]; then
    echo ""
    echo "WARNING: unknown skills in consumer (not godogen, not a known sibling):"
    printf '  - %s\n' "${orphans[@]}"
    echo "If these are genuinely orphaned (skill removed from godogen), delete manually."
fi

cp "$CLAUDE_MD" "$TARGET/CLAUDE.md"
echo "Created CLAUDE.md (from $CLAUDE_MD)"

if [ ! -f "$TARGET/.gitignore" ]; then
    cat > "$TARGET/.gitignore" << 'GI_EOF'
.claude
CLAUDE.md
assets
screenshots
.godot
*.import
GI_EOF
    echo "Created .gitignore"
fi

git -C "$TARGET" init -q 2>/dev/null || true

echo "Done. skills installed in $TARGET/.claude/skills/: $(ls "$TARGET/.claude/skills/" | wc -l)"
