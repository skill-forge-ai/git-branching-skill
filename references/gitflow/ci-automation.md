# CI automation

One-click GitFlow: the mechanical parts of the lifecycle become buttons, so engineers supply
judgment (which version, when to promote) and nothing else.

> **Platform status.** The GitLab examples derive from a pattern running in production. The GitHub
> Actions examples are **translations that have not been run** — the semantics differ in ways noted
> inline. Treat them as a starting point, not battle-tested config.

## Jobs

| Job | Trigger | Does |
|---|---|---|
| `cut-release` | manual from `develop`, takes a version | cut `release/x.y.z` → bump → first prerelease tag |
| `cut-hotfix` | manual from `main`, takes a ticket | derive PATCH+1 → cut `hotfix/*` **and** `release/x.y.z+1` → bump → open the `hotfix → release` MR |
| `prerelease:tag` | automatic on push to `release/*` | increment within the current channel |
| `promote:beta` / `promote:rc` | manual on the release branch | switch channel, reset to `.0`, refuse downgrade |
| `release:prod` | manual | **G5 content gate** → final tag → production deploy |
| `mergeback` | automatic after a successful production deploy | open `release→main` and `release→develop` |

## Two design decisions worth stating

**1. Channel state lives in git tags, not a state file.** The current channel is read from the most
recent tag; ordering is `alpha < beta < rc < final`. Nothing to desync, and `promote` can refuse a
downgrade by comparing channels. A state file would be one more thing to get wrong.

**2. Version derivation is asymmetric, deliberately.** `cut-release` takes an explicit version —
choosing MINOR vs MAJOR is a judgment call about the batch being shipped. `cut-hotfix` takes none —
PATCH+1 is mechanical. Automate the mechanical decision, keep the judgment call human.

This matters most for hotfixes: they are written under time pressure, exactly when a hand-typed
version gets fumbled, and a wrong final tag cannot be recalled.

## Bump runs exactly once, at cut time

Writing the version anywhere else produces a version that disagrees with its tag. Bump writes the
language-specific source **and** syncs the lockfile in the same commit:

| Ecosystem | Version source | Lockfile sync |
|---|---|---|
| Python (uv) | `pyproject.toml` | `uv lock && uv sync` |
| Node (npm) | `package.json` | `npm install --package-lock-only` |
| Node (pnpm) | `package.json` | `pnpm install --lockfile-only` |
| Java (Maven) | `pom.xml` | `mvn versions:set` (keep `-SNAPSHOT`; the tag is the real version) |

If a project's version lives only in tags, there is no bump step — the premise is absent.

## The G5 gate in CI

The single most important job condition. **Canonical implementation — other files reference this one
rather than restating it:**

```bash
# explicit refspec: plain `git fetch origin main` writes FETCH_HEAD and can leave
# origin/main stale, which makes this gate silently pass on a shallow CI clone
git fetch origin +refs/heads/main:refs/remotes/origin/main
MISSING=$(git log --oneline --cherry-pick --right-only --no-merges HEAD...origin/main)
if [ -n "$MISSING" ]; then
  echo "BLOCKED: main has commits this release never received:"
  echo "$MISSING"
  exit 1
fi
```

Two wrong implementations, both of which fire on healthy releases and train the team to bypass:

```bash
# ✗ ancestry, not content — fails after any --no-ff back-merge
git merge-base --is-ancestor origin/main HEAD || exit 1

# ✗ three-dot diff = `git diff $(git merge-base HEAD main) main`. It compares the
#   MERGE BASE to main and never reads the release side, so it reports what main
#   changed rather than what the release lacks
git diff HEAD...origin/main --name-only
```

`--cherry-pick` compares by patch-id, so a fix the release obtained by another route (cherry-pick,
independent re-application) is correctly treated as present.

Provide no override flag — an override on a gate that fires spuriously becomes the default path, and
the gate is then already disabled when real drift appears (P10 → P9). Provide the reconciliation
procedures instead (SKILL.md, "Getting past a gate legitimately").

## GitLab CI

```yaml
variables:
  RELEASE_VERSION:
    value: ""
    description: "Target version, bare x.y.z (no leading v, no suffix)"

cut-release:
  stage: release
  rules:
    - if: '$CI_COMMIT_BRANCH == "develop"'
      when: manual
  script:
    - test -n "$RELEASE_VERSION" || { echo "RELEASE_VERSION required"; exit 1; }
    - echo "$RELEASE_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || exit 1
    - git fetch origin --tags
    - git checkout -b "release/$RELEASE_VERSION" "origin/develop"
    - ./scripts/bump_version.sh "$RELEASE_VERSION"
    - git commit -am "chore: bump version to $RELEASE_VERSION"
    - git push origin "release/$RELEASE_VERSION"
    - git tag "v$RELEASE_VERSION-alpha.0" && git push origin "v$RELEASE_VERSION-alpha.0"

cut-hotfix:
  stage: release
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      when: manual
  script:
    - test -n "$TICKET" || { echo "TICKET required"; exit 1; }
    - git fetch origin --tags
    # Highest final tag reachable from main. NOT `git describe`: it returns the
    # topologically NEAREST tag, so after a --no-ff release merge it can pick an
    # older tag off the first-parent path. --sort=-v:refname sorts by version.
    # The grep is the real filter: --match takes a GLOB, so 'v[0-9]*.[0-9]*.[0-9]*'
    # still matches v1.2.0-rc.1 (the trailing * swallows the suffix).
    - LAST=$(git tag --merged origin/main --sort=-v:refname | grep -Ex 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    - test -n "$LAST" || { echo "no final tag reachable from main"; exit 1; }
    # awk validates NF==3 and numeric patch, then exits 1 rather than emitting
    # garbage. Bare `awk -F. '{print $1"."$2"."$3+1}'` silently turns
    # v1.4.0-rc.2 into 1.4.1 and an empty input into ..1
    - NEXT=$(printf '%s' "${LAST#v}" | awk -F. 'NF==3 && $3 ~ /^[0-9]+$/ {print $1"."$2"."$3+1; f=1} END{if(!f) exit 1}')
    - test -n "$NEXT" || { echo "unparseable tag: $LAST"; exit 1; }
    - git ls-remote --exit-code origin "refs/heads/release/$NEXT" && { echo "release/$NEXT exists"; exit 1; }
    - git checkout -b "hotfix/$TICKET" "origin/main" && git push origin "hotfix/$TICKET"
    - git checkout -b "release/$NEXT" "origin/main"
    - ./scripts/bump_version.sh "$NEXT"
    - git commit -am "chore: bump version to $NEXT"
    - git push origin "release/$NEXT"
    - ./scripts/open_mr.sh "hotfix/$TICKET" "release/$NEXT" --squash

release:prod:
  stage: deploy
  rules:
    - if: '$CI_COMMIT_BRANCH =~ /^release\//'
      when: manual
  script:
    - git fetch origin +refs/heads/main:refs/remotes/origin/main
    - |
      MISSING=$(git log --oneline --cherry-pick --right-only --no-merges HEAD...origin/main)
      if [ -n "$MISSING" ]; then
        echo "BLOCKED: main has commits this release never received:"; echo "$MISSING"; exit 1
      fi
    - VERSION="${CI_COMMIT_BRANCH#release/}"
    - git tag "v$VERSION" && git push origin "v$VERSION"

deploy:prod:
  stage: deploy
  environment: production          # approval gate
  rules:
    - if: '$CI_COMMIT_TAG =~ /^v[0-9]+\.[0-9]+\.[0-9]+$/'   # anchored — excludes -rc.N (P5)
  script:
    - ./deploy.sh
```

**Write-operation note:** on some self-hosted instances, tokens passed on the `glab` command line get
mangled by log-masking and every write returns 401. Reads are fine. Put writes in a script using an
explicit header (`curl --header "PRIVATE-TOKEN: $TOKEN"`) rather than debugging the CLI.

## GitHub Actions

**Untested translation.** Three semantic gaps to close before relying on it:

1. **No `when: manual` on a job.** GitLab's manual job with a form variable becomes a separate
   `workflow_dispatch` workflow with `inputs` — the operator clicks in a different place.
2. **Tag filters are globs, not regex.** `'v[0-9]+.[0-9]+.[0-9]+'` does **not** anchor;
   `v1.2.3-rc.1` can still match. Re-check inside the job (P5).
3. **`GITHUB_TOKEN` pushes do not trigger downstream workflows** by design. A tag pushed by
   `cut-release` will not start the deploy workflow — use a PAT or `repository_dispatch`. This one
   fails silently.

```yaml
name: cut-release
on:
  workflow_dispatch:
    inputs:
      version:
        description: "Target version, bare x.y.z"
        required: true

jobs:
  cut:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: develop
          fetch-depth: 0                     # required: default shallow clone breaks tag lookup
          token: ${{ secrets.RELEASE_PAT }}  # not GITHUB_TOKEN — see gap 3
      - run: |
          echo "${{ inputs.version }}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || exit 1
          git checkout -b "release/${{ inputs.version }}"
          ./scripts/bump_version.sh "${{ inputs.version }}"
          git commit -am "chore: bump version to ${{ inputs.version }}"
          git push origin "release/${{ inputs.version }}"
          git tag "v${{ inputs.version }}-alpha.0"
          git push origin "v${{ inputs.version }}-alpha.0"
```

```yaml
name: release-prod
on:
  workflow_dispatch:

jobs:
  gate-and-tag:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0, token: "${{ secrets.RELEASE_PAT }}" }
      - name: G5 content gate
        run: |
          git fetch origin +refs/heads/main:refs/remotes/origin/main
          MISSING=$(git log --oneline --cherry-pick --right-only --no-merges HEAD...origin/main)
          if [ -n "$MISSING" ]; then
            echo "BLOCKED: main has commits this release never received:"; echo "$MISSING"; exit 1
          fi
      - name: Tag
        run: |
          VERSION="${GITHUB_REF_NAME#release/}"
          git tag "v$VERSION" && git push origin "v$VERSION"
```

Production deploy uses `environment:` with required reviewers for the approval gate, and must re-test
the tag shape in-job because the `on.push.tags` glob cannot anchor.

## Failure modes to build in

- **`cut-hotfix` when the target release branch already exists** → fail loudly, never force-create.
  Two hotfixes racing, or a hotfix colliding with an in-flight release, need a human.
- **Version derived from the wrong tag** → always `--match 'v[0-9]*.[0-9]*.[0-9]*'` against
  `origin/main`. The newest tag in the repo may be a prerelease for a different, larger version.
- **Prerelease tag reaching production** → anchor the pattern (P5).
- **Pipeline silently not created** → protected CI variables invisible to unprotected refs (P7).
