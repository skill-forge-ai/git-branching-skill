#!/usr/bin/env bash
# Verify install.sh lists exactly the markdown files present in the repo.
# Run before committing a file addition or rename.
set -euo pipefail
cd "$(dirname "$0")/.."

actual=$(find SKILL.md references -name '*.md' | sort)
listed=$(sed -n '/^FILES=(/,/^)/p' install.sh | grep -oE '"[^"]+\.md"' | tr -d '"' | sort)

if [ "$actual" = "$listed" ]; then
  echo "OK: install.sh covers all $(echo "$actual" | wc -l | tr -d ' ') files"
  exit 0
fi

echo "MISMATCH between repo layout and install.sh FILES list:"
comm -23 <(echo "$actual") <(echo "$listed") | sed 's/^/  missing from install.sh: /'
comm -13 <(echo "$actual") <(echo "$listed") | sed 's/^/  listed but absent:      /'
exit 1
