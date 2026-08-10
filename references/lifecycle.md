# Lifecycle

Step-by-step procedures with per-step verification. Full profile is the reference; Lean and
Merged-staging drop the prerelease steps, never the gates.

## Ordering rule

**Tag on the release branch → deploy prod → then merge to `main` and `develop`.**

Merging first puts unshipped code on `main`, breaking "main = what is in production". AWS states it
directly: *"After the release branch has deployed to production, it should be merged back into the
develop and main branches."*

A known variant merges to `main` first and tags there, keeping `main` equal to verified production
code. It is defensible, but it inverts the failure mode: a deploy that fails after the merge leaves
`main` describing a production state that never existed. Prefer the default; if a project runs the
variant, follow it and keep the C5 gate either way.

## Release

```bash
# 1. Cut from the remote ref, never a stale local branch (P3)
git fetch origin --tags --prune
git checkout -b release/1.4.0 origin/develop
```

Version choice is a judgment call: a batch of features is MINOR, not PATCH. Derive from the last
**final** tag — experimental prerelease tags are not a baseline.

```bash
# 2. Bump once, here, with the lockfile in the same commit
#    uv lock | npm install --package-lock-only | pnpm install --lockfile-only | mvn versions:set
git commit -am "chore: bump version to 1.4.0"
git push -u origin release/1.4.0
```

```bash
# 3. First prerelease tag → deploys to the test environment
git tag v1.4.0-alpha.0 && git push origin v1.4.0-alpha.0
```

**Verify:** the pipeline actually got created. Silence usually means protected CI variables (P7).

```bash
# 4. Fixes during stabilization: cut from the release, squash back into it
git checkout -b bugfix/1234_null_check release/1.4.0
# ... fix, review, squash-merge into release/1.4.0 → re-tag alpha.1, beta.N, rc.N
```

Channels each restart at `.0` (`alpha.2 → beta.0`), and promotion must refuse a downgrade. Ordering
is `alpha < beta < rc < final`.

```bash
# 5. C5 gate — MANDATORY before the final tag
git fetch origin +refs/heads/main:refs/remotes/origin/main
git log --oneline --cherry-pick --right-only --no-merges HEAD...origin/main   # empty → safe to tag
```

Non-empty output names commits on `main` this release never received. Merge them in, no squash,
re-run CI, then tag:

```bash
git merge --no-ff origin/main
git push origin release/1.4.0
```

A populated `git log HEAD..origin/main` with an empty file diff is benign — see SKILL.md C5.

```bash
# 6. Final tag → production deploy (through the approval gate)
git tag v1.4.0 && git push origin v1.4.0
```

**Verify deploy succeeded before proceeding.** Steps 7–8 record a production state; running them
against a failed deploy makes `main` lie.

```bash
# 7-8. Merge back — both targets, no squash (C3), as soon as possible
git checkout main    && git merge --no-ff release/1.4.0 && git push origin main
git checkout develop && git merge --no-ff release/1.4.0 && git push origin develop
```

**Verify before deleting the release branch:**

```bash
git log --oneline --cherry-pick --right-only origin/develop...release/1.4.0   # empty = fully absorbed
```

## Hotfix

Two branches from `main`, one action:

```bash
git fetch origin --tags --prune
git checkout -b hotfix/5678_payment_null origin/main
git checkout -b release/1.4.1 origin/main
```

Version is mechanical: PATCH+1 from the latest final tag **reachable from `main`** — not the newest
tag in the repo, which may belong to an in-flight release for the next MINOR.

```bash
git tag --merged origin/main --sort=-v:refname | grep -Ex 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1
```

**Not `git describe --abbrev=0`.** It returns the topologically *nearest* tag, so after a `--no-ff`
release merge it can pick an older tag sitting on the first-parent path — versioning a hotfix *below*
what is live. And its `--match` takes a glob, not a regex: `'v[0-9]*.[0-9]*.[0-9]*'` still matches
`v1.2.0-rc.1`, because the trailing `*` swallows the suffix.

Fix on `hotfix/*`, squash-merge into `release/1.4.1` (low→high, squash correct per C3), then the
carrier runs the normal ladder: prerelease tags if the profile has them, C5 gate, final tag, deploy,
merge back to **both** `main` and `develop`.

Why the carrier: gates, promotion jobs, and mergeback are written against `release/*`. Tagging the
hotfix branch directly would require duplicating every one of those rules for a second branch
pattern.

**C5 still applies** — least likely to trip here, since the branch was just cut from `main`, but a
slow hotfix ladder can be overtaken by a second hotfix landing on `main`.

**If a release is already active**, a hotfix competes with it for a shared test environment. Either
serialize, or give the hotfix its own environment. This is the collision AWS warns about.

## Bugfix vs hotfix

| | Bugfix | Hotfix |
|---|---|---|
| Fixes | a release not yet in production | code live in production |
| Cut from | the active `release/*` | `main` |
| Merges into | that release branch | its own `release/x.y.z+1` carrier |
| Version | none — release keeps its number | PATCH+1 |

**When an active release branch exists, fixes for it target it, not `develop`** — otherwise the fix
never reaches the environment under test (P1).

## Back-merge

Mandatory after every production deploy, both `main` and `develop`, no squash, as soon as possible.

Two claims to reject:

- *"Everything came from develop, so it's a no-op."* Release branches accumulate commits never on
  develop: QA fixes, the version bump, and any hotfix merged in from `main`.
- *"Develop moved on, merge is painful, we'll cherry-pick if needed."* Cherry-picking requires
  knowing something is missing; the failure mode is a fixed bug reappearing weeks later with nobody
  connecting it to the skipped merge.

```bash
git log --oneline --cherry-pick --right-only origin/develop...release/1.4.0
```

`--cherry-pick` drops commits whose patch already exists on the other side. The guarantee runs one
way only: **empty means absorbed; non-empty means *possibly* absent.** Patch-ids change when a
cherry-pick resolved conflicts differently, and a squash merge collapses many commits into one
patch-id that matches none of them — so a squashed back-merge reports everything as missing.

Confirm a non-empty result before acting on it:

```bash
git diff origin/develop..release/1.4.0 --stat   # empty tree diff = content is there
```

Never delete the release branch until one of the two checks is clean.

When `develop` has genuinely diverged far, cherry-picking specific commits is an acceptable
alternative to a wholesale merge — verify with `git diff --stat` that nothing unrelated came along
(P4).
