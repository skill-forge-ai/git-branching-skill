#!/usr/bin/env bash
# Install the git-branching skill for Claude Code, Codex, Cursor, or any agent that
# reads skills from a directory.
#
#   curl -fsSL https://raw.githubusercontent.com/skill-forge-ai/git-branching-skill/main/install.sh | bash
#
# Options (environment variables):
#   INSTALL_DIR=/path   install somewhere specific
#   AGENT=codex         shorthand for ~/.codex/skills   (claude | codex | cursor)
#   BRANCH=some-branch  install from a different branch
#   REPO=owner/name     install from a fork
set -euo pipefail

REPO="${REPO:-skill-forge-ai/git-branching-skill}"
BRANCH="${BRANCH:-main}"
SKILL_NAME="git-branching"

# Files to install. Keep in sync with the repo layout; verified by scripts/check-install.sh
FILES=(
  "SKILL.md"
  "references/detection.md"
  "references/choosing.md"
  "references/pitfalls.md"
  "references/aws-baseline.md"
  "references/handbook-zh.md"
  "references/gitflow/lifecycle.md"
  "references/gitflow/ci-automation.md"
  "references/gitflow/recovery.md"
  "references/gitflow/profiles.md"
  "references/gitflow/joint-release.md"
  "references/github-flow/lifecycle.md"
  "references/github-flow/ci-automation.md"
  "references/github-flow/recovery.md"
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

# This skill was previously published as "gitflow". Warn rather than delete, so a
# user who customized the old copy decides what happens to it.
OLD="$(dirname "$TARGET")/gitflow"
if [ -d "$OLD" ] && [ "$OLD" != "$TARGET" ]; then
  echo "Note: an older 'gitflow' skill exists at ${OLD}."
  echo "      It is superseded by this one. Remove it once you have checked for local edits:"
  echo "      rm -rf ${OLD}"
fi

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
  - identifying or adopting a repo's branching strategy (GitFlow vs GitHub Flow)
  - cutting or tagging a release, or shipping a hotfix
  - merging back to develop or main, or opening a PR into a protected main
  - debugging a release gate, a tag pipeline, or a required check that stopped blocking
  - recovering: production rollback, bad commit on main, racing hotfixes
  - deciding between the two strategies, or migrating from one to the other

Start here:  ${TARGET}/SKILL.md
EOF
