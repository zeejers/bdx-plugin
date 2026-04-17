#!/bin/bash
# release.sh — bump plugin version, stage changes, regenerate changelog.
#
# Usage:
#   ./scripts/release.sh patch|minor|major
#   ./scripts/release.sh set <version>
#
# Finds every plugin.json under .claude-plugin/ (supports multi-plugin repos),
# bumps each version field consistently, stages all changes with `git add .`,
# then runs `lazy-changelog --prepend CHANGELOG.md`. Commit + tag + push is
# left to the caller so you can review the changelog first.

set -euo pipefail

MODE="${1:-}"
TARGET="${2:-}"

case "$MODE" in
  patch|minor|major|set) ;;
  *) echo "usage: $0 patch|minor|major|set <version>" >&2; exit 2 ;;
esac

if [ "$MODE" = "set" ] && [ -z "$TARGET" ]; then
  echo "error: 'set' requires a version argument" >&2; exit 2
fi

# Locate plugin manifests (one per plugin in a multi-plugin repo).
# Using while-read instead of mapfile for bash 3.2 compat (macOS default).
MANIFESTS=()
while IFS= read -r line; do
  MANIFESTS+=("$line")
done < <(find .claude-plugin -maxdepth 2 -name 'plugin.json' -type f | sort)
if [ "${#MANIFESTS[@]}" -eq 0 ]; then
  echo "error: no plugin.json found under .claude-plugin/" >&2; exit 1
fi

# Current version (authoritative: first manifest; assume all are in lockstep)
CURRENT=$(jq -r .version "${MANIFESTS[0]}")
if [ -z "$CURRENT" ] || [ "$CURRENT" = "null" ]; then
  echo "error: ${MANIFESTS[0]} has no .version field" >&2; exit 1
fi

bump() {
  local cur="$1" part="$2" major minor patch
  IFS='.' read -r major minor patch <<< "$cur"
  case "$part" in
    patch) echo "$major.$minor.$((patch + 1))" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    major) echo "$((major + 1)).0.0" ;;
  esac
}

if [ "$MODE" = "set" ]; then
  NEW="$TARGET"
else
  NEW=$(bump "$CURRENT" "$MODE")
fi

echo "Bumping $CURRENT → $NEW across ${#MANIFESTS[@]} manifest(s):"
for m in "${MANIFESTS[@]}"; do
  echo "  $m"
  tmp=$(mktemp)
  jq --arg v "$NEW" '.version = $v' "$m" > "$tmp"
  mv "$tmp" "$m"
done

echo
echo "git add ."
git add .

echo "lazy-changelog generate --prepend CHANGELOG.md"
lazy-changelog generate --prepend CHANGELOG.md

echo
echo "Done. Next steps:"
echo "  git diff --staged         # review"
echo "  git commit -m 'release v$NEW'"
echo "  git tag v$NEW"
echo "  git push && git push --tags"
