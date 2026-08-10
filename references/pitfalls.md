# Pitfalls

Symptom → root cause → handling. Field-collected; tool-specific entries name the tool.

## P1 — Fix merged, but the environment under test never gets it

**Root cause:** the fix targeted `develop` while a `release/*` was actively iterating. Once a release
branch is the active test vehicle, it — not `develop` — is what deploys to the test environment.

**Handling:** when an active release branch exists, branch fixes from it and target it
(`bugfix/* → release/x.y.z`, squash). The fix reaches `develop` later via back-merge. Check first:

```bash
git branch -r --list '*release/*'
```

## P2 — New CI rules never fire for tags

**Root cause:** a tag pipeline reads the CI config **from the tagged commit**. Routing rules that
exist only on `develop` cannot affect a tag built from `main`.

**Handling:** the CI-bootstrap exception — pipeline-definition changes may merge directly to `main`,
then back-merge.

**Bounded by a positive allowlist, not by "no business logic"** — that phrasing reads narrow and is
in practice enormous. Only these qualify:

- `.gitlab-ci.yml`, `.github/workflows/*`, and files they `include:`
- scripts invoked solely by those pipelines

**Explicitly not covered**, because each changes runtime behaviour as surely as source code:
Dockerfiles and base-image bumps, dependency manifests and lockfiles, Terraform and other IaC, k8s
manifests, `.env` templates, entrypoint scripts, healthcheck definitions. These go through the normal
branch flow.

A commit mixing allowlisted and non-allowlisted files must be split. Mixing is how the branch model
gets bypassed under cover of "it's just CI".

## P3 — Branch cut from a stale local `main`, hundreds of commits behind

**Handling:** always cut from the remote ref after fetching.

```bash
git fetch origin
git checkout -b release/x.y.z origin/develop   # or origin/main for hotfix
```

## P4 — Back-merge MR is enormous and conflict-ridden

**Root cause:** the target branch is far behind, so the merge drags in unrelated history.

**Handling:** cherry-pick the specific commits instead of merging wholesale — then verify the
cherry-pick didn't carry unrelated deletions:

```bash
git diff --stat <target>..HEAD    # inspect before pushing
```

## P5 — A prerelease tag triggers the production job

**Root cause:** the production rule tests "is there a tag" rather than the tag's shape, so
`v1.4.0-rc.1` matches.

**Handling:** anchor the pattern.

```yaml
# GitLab
rules:
  - if: '$CI_COMMIT_TAG =~ /^v[0-9]+\.[0-9]+\.[0-9]+$/'
```

```yaml
# GitHub Actions — glob only, no anchors; re-check in the job
on:
  push:
    tags: ['v[0-9]+.[0-9]+.[0-9]+']
```

The Actions glob does **not** anchor — `v1.2.3-rc.1` can still match. Re-verify inside the job with a
real regex before deploying.

## P6 — CLI refuses to merge citing a failing pipeline, but the server allows it

**Root cause (GitLab/`glab`):** client-side precheck. A release pipeline showing `manual` — a gated
production job waiting on a human — is not a failure, but the CLI treats non-success as blocking.

**Handling:** check server state, then merge via API or UI.

```bash
glab api "projects/<id>/merge_requests/<iid>" | jq -r '.detailed_merge_status'
# mergeable → the server is fine; the CLI is wrong
glab api --method PUT "projects/<id>/merge_requests/<iid>/merge"
```

Only affects human merges. CI automation using `create`-style calls never hits this precheck.

## P7 — Tag pipeline silently doesn't run at all

**Root cause:** CI variables marked *protected* are invisible to unprotected tags and branches. The
job can't resolve them, and the pipeline is never created — no error, no pipeline.

**Handling:** either unprotect the variables or protect the prerelease tag pattern. Diagnose by
comparing a working tag with a failing one; silence rather than failure is the signature.

## P8 — A feature that shipped is missing after the next release

**Root cause:** back-merge was skipped (C4).

**Handling:** back-merge immediately after every production deploy. Verify:

```bash
git log --oneline --cherry-pick --right-only origin/develop...release/x.y.z
```

`--cherry-pick` drops commits whose patch already exists on the other side, so remaining output is
genuinely absent.

## P9 — A production deploy silently reverts a hotfix that was live an hour ago

**Root cause:** the final tag was cut from a release branch missing `main`'s content. C5 was absent or
bypassed.

**Handling:** merge `main` → `release/*` (no squash), re-run CI, tag the next patch. The bad tag is
immutable — move forward, don't delete.

## P10 — The "main ⊆ release" gate fails on *every* release, so the team routinely bypasses it

**Root cause:** implemented as `git merge-base --is-ancestor origin/main HEAD`, or as
`git diff HEAD...origin/main`. After a `--no-ff` back-merge, main's merge commit is not an ancestor
of a release later cut from `develop` — the content arrived, the commit did not. Three-dot diff has
its own version of the same flaw: it compares the *merge base* to main and never reads the release
side at all.

**Handling:** replace with the content check (SKILL.md, C5). Do not override.

**The half-fix to avoid.** The natural next step — and the one teams actually reach — is
`git diff HEAD...origin/main`, often with a comment explaining that it lets no-diff mergeback nodes
through. The instinct is right and it does fix the spurious failures. But three-dot diff expands to
`git diff $(git merge-base HEAD main) main`: it compares the *merge base* to main and never reads the
release side, so it reports what main changed rather than what the release lacks. A release that
inherited a hotfix and then removed that code passes cleanly. Trading a noisy false positive for a
silent false negative is the worse trade — P9 is exactly what gets through.

**This bug causes P9 rather than preventing it.** A gate that always fires trains everyone to bypass
it, so it is already disabled on the day real drift appears. Two tempting misreadings, both wrong:

- *"It's a false positive, so skip it"* — correct diagnosis, wrong fix. Replace the check.
- *"It fails every release, so the team must be skipping back-merges"* — blames people for a tooling
  bug. Run the canonical gate (SKILL.md C5) before concluding anything.
