#!/usr/bin/env bash
# Install the gitflow skill for Claude Code, Codex, Cursor, or any agent that
# reads skills from a directory.
#
#   curl -fsSL https://raw.githubusercontent.com/PeterHiroshi/gitflow-skill/main/install.sh | bash
#
# Options (environment variables):
#   INSTALL_DIR=/path   install somewhere specific
#   AGENT=codex         shorthand for ~/.codex/skills   (claude | codex | cursor)
#   BRANCH=some-branch  install from a different branch
#   REPO=owner/name     install from a fork
set -euo pipefail

REPO="${REPO:-PeterHiroshi/gitflow-skill}"
BRANCH="${BRANCH:-main}"
SKILL_NAME="gitflow"

# Files to install. Keep in sync with the repo layout; verified by scripts/check-install.sh
FILES=(
  "SKILL.md"
  "references/lifecycle.md"
  "references/ci-automation.md"
  "references/recovery.md"
  "references/pitfalls.md"
  "references/profiles.md"
  "references/joint-release.md"
  "references/aws-baseline.md"
)

# Resolve install directory: explicit > AGENT shorthand > autodetect > claude default
if [ -n "${INSTALL_DIR:-}" ]; then
  TARGET="$INSTALL_DIR"
else
  case "${AGENT:-}" in
    codex)  BASE="${HOME}/.codex/skills" ;;
    cursor) BASE="${HOME}/.cursor/skills" ;;
    claude) BASE="${HOME}/.claude/skills" ;;
    "")
      if   [ -d "${HOME}/.claude" ]; then BASE="${HOME}/.claude/skills"
      elif [ -d "${HOME}/.codex"  ]; then BASE="${HOME}/.codex/skills"
      elif [ -d "${HOME}/.cursor" ]; then BASE="${HOME}/.cursor/skills"
      else BASE="${HOME}/.claude/skills"
      fi ;;
    *) echo "Unknown AGENT: ${AGENT} (use claude, codex, or cursor)" >&2; exit 1 ;;
  esac
  TARGET="${BASE}/${SKILL_NAME}"
fi

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }

echo "Installing ${SKILL_NAME} skill to ${TARGET}"

# Download to a staging dir first, so a network failure never leaves a
# half-installed or deleted skill behind.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
for f in "${FILES[@]}"; do
  mkdir -p "${STAGE}/$(dirname "$f")"
  if ! curl -fsSL "${BASE_URL}/${f}" -o "${STAGE}/${f}"; then
    echo "Failed to download ${f} from ${REPO}@${BRANCH}" >&2
    exit 1
  fi
done

# Sanity check: SKILL.md must have frontmatter, or we fetched an error page.
head -1 "${STAGE}/SKILL.md" | grep -q '^---$' || {
  echo "Downloaded SKILL.md does not look like a skill file" >&2; exit 1; }

# Swap in only after every file arrived intact.
mkdir -p "$(dirname "$TARGET")"
rm -rf "$TARGET"
mv "$STAGE" "$TARGET"
chmod -R u+rw "$TARGET"
trap - EXIT

cat <<EOF

Installed ${#FILES[@]} files to ${TARGET}

The skill activates when you are:
  - cutting or tagging a release, or shipping a hotfix
  - merging back to develop or main
  - deciding whether a fix belongs on develop or the active release branch
  - identifying or adopting a repo's branching strategy
  - debugging a release gate that fails or a tag pipeline that did not run
  - recovering: production rollback, abandoned release, racing hotfixes

Start here:  ${TARGET}/SKILL.md
EOF
