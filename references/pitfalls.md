# Pitfalls

Symptom → root cause → handling. Field-collected; tool-specific entries name the tool.

**Each entry is tagged with the strategy it applies to.** A GitFlow pitfall cited in a GitHub Flow
repo is noise at best and wrong advice at worst — P1's "target the active release branch" has no
meaning where none exists.

| Tag | Applies to |
|---|---|
| **[GitFlow]** | release branches, back-merge, the content gate |
| **[GitHub Flow]** | the gate, branch lifetime, flags, revert |
| **[Both]** | anything resting on U1–U4 |

## P1 [GitFlow] — Fix merged, but the environment under test never gets it

**Root cause:** the fix targeted `develop` while a `release/*` was actively iterating. Once a release
branch is the active test vehicle, it — not `develop` — is what deploys to the test environment.

**Handling:** when an active release branch exists, branch fixes from it and target it
(`bugfix/* → release/x.y.z`, squash). The fix reaches `develop` later via back-merge. Check first:

```bash
git branch -r --list '*release/*'
```

## P2 [GitFlow] — New CI rules never fire for tags

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

## P3 [Both] — Branch cut from a stale local `main`, hundreds of commits behind

**Handling:** always cut from the remote ref after fetching.

```bash
git fetch origin
git checkout -b release/x.y.z origin/develop   # or origin/main for hotfix
```

## P4 [GitFlow] — Back-merge MR is enormous and conflict-ridden

**Root cause:** the target branch is far behind, so the merge drags in unrelated history.

**Handling:** cherry-pick the specific commits instead of merging wholesale — then verify the
cherry-pick didn't carry unrelated deletions:

```bash
git diff --stat <target>..HEAD    # inspect before pushing
```

## P5 [GitFlow] — A prerelease tag triggers the production job

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

## P6 [Both] — CLI refuses to merge citing a failing pipeline, but the server allows it

**Root cause (GitLab/`glab`):** client-side precheck. A release pipeline showing `manual` — a gated
production job waiting on a human — is not a failure, but the CLI treats non-success as blocking.

**Handling:** check server state, then merge via API or UI.

```bash
glab api "projects/<id>/merge_requests/<iid>" | jq -r '.detailed_merge_status'
# mergeable → the server is fine; the CLI is wrong
glab api --method PUT "projects/<id>/merge_requests/<iid>/merge"
```

Only affects human merges. CI automation using `create`-style calls never hits this precheck.

## P7 [GitFlow] — Tag pipeline silently doesn't run at all

**Root cause:** CI variables marked *protected* are invisible to unprotected tags and branches. The
job can't resolve them, and the pipeline is never created — no error, no pipeline.

**Handling:** either unprotect the variables or protect the prerelease tag pattern. Diagnose by
comparing a working tag with a failing one; silence rather than failure is the signature.

## P8 [GitFlow] — A feature that shipped is missing after the next release

**Root cause:** back-merge was skipped (G4).

**Handling:** back-merge immediately after every production deploy. Verify:

```bash
git log --oneline --cherry-pick --right-only origin/develop...release/x.y.z
```

`--cherry-pick` drops commits whose patch already exists on the other side, so remaining output is
genuinely absent.

## P9 [GitFlow] — A production deploy silently reverts a hotfix that was live an hour ago

**Root cause:** the final tag was cut from a release branch missing `main`'s content. G5 was absent or
bypassed.

**Handling:** merge `main` → `release/*` (no squash), re-run CI, tag the next patch. The bad tag is
immutable — move forward, don't delete.

## P10 [GitFlow] — The "main ⊆ release" gate fails on *every* release, so the team routinely bypasses it

**Root cause:** implemented as `git merge-base --is-ancestor origin/main HEAD`, or as
`git diff HEAD...origin/main`. After a `--no-ff` back-merge, main's merge commit is not an ancestor
of a release later cut from `develop` — the content arrived, the commit did not. Three-dot diff has
its own version of the same flaw: it compares the *merge base* to main and never reads the release
side at all.

**Handling:** replace with the content check (SKILL.md, G5). Do not override.

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
  bug. Run the canonical gate (SKILL.md G5) before concluding anything.

## P11 [GitHub Flow] — A required check silently stopped being required

**Root cause:** branch protection references a check by **job name**. Renaming the job, moving it to
another workflow file, or splitting it into a matrix changes that name, and the protection rule now
requires a check that no longer reports. The merge button turns green.

Nothing fails. The PR shows its own CI passing, and the rule shows as configured — it is only the
*join* between them that is broken.

**Handling:** after any workflow rename, diff the configured contexts against what actually reported.

```bash
gh api repos/{owner}/{repo}/branches/main/protection --jq '.required_status_checks.contexts[]' | sort > /tmp/required
gh pr view <recent-pr> --json statusCheckRollup \
  --jq '.statusCheckRollup[] | (.name // .context)' | sort -u > /tmp/reported
comm -23 /tmp/required /tmp/reported     # required but never reports = the gate is open
```

Treat a non-empty left column as an open `main`, not as a config typo.

## P12 [GitHub Flow] — The branch passed CI, the merge broke `main`

**Root cause:** the check ran against the branch tip, which was based on an older `main`. Two
independently-green changes conflict semantically — not textually, so there is no merge conflict to
notice.

**Handling:** enable "require branches to be up to date before merging" (`strict: true`), and use
`pull_request` triggers, which build the **merge result** rather than the branch. The cost is a
re-run per merge; the alternative is discovering the interaction in production, which H1 forbids.

Merge queues solve this properly at higher volume. Below that volume, `strict: true` is enough.

## P13 [GitHub Flow] — A "temporary" long-lived branch became a release branch

**Root cause:** a feature was judged too big to merge incrementally, so the branch stayed open for
weeks. It is now a release branch: it diverges, it needs its own testing, and merging it is an event.
But none of GitFlow's rules apply to it — no freeze band, no back-merge, no content gate.

**The tell:** people talk about "merging the X branch" as a scheduled event with a risk discussion.
That is a release, and it is unprotected.

**Handling:** split it and land the parts behind a flag (H3). If genuinely impossible, that is
evidence the repo needs GitFlow — decide at the repo level (`choosing.md`), do not run one branch
under different rules.

```bash
git branch -r --no-merged origin/main    # the honest list
```

## P14 [GitHub Flow] — Turning the flag off did not turn the feature off

**Root cause:** one of two shapes, both of which pass every test that runs with the flag *on*:

- the flag is read once at process start, so changing it needs a restart — a deploy with extra steps
- the flagged path wrote data the unflagged path cannot read, so turning it off strands or corrupts
  that data

**Handling:** read flags per-request, and **test the off path** on a schedule — a flag nobody has
turned off since launch is an untested rollback. For any flag near a schema or a write path, the
off-state has to be exercised, not assumed; make the migration safe in both states (expand/contract)
rather than relying on the boolean.

## P15 [GitHub Flow] — Re-merging a reverted branch lands nothing

**Root cause:** the revert is in history. Merging the original branch again presents content git
already sees as present-then-removed-by-decision, so the merge is a no-op or drops the change again.

**Handling:** revert the revert on a fresh branch, fix the original defect in the same PR, and take it
through the gate.

```bash
git revert <the-revert-sha>    # then fix forward on top — never ship a bare revert-of-revert
```

A bare revert-of-revert re-ships the original bug, which is how the same outage happens twice in a
week.

## P16 [GitHub Flow] — Two deploys raced and production matches no commit

**Root cause:** two merges landed close together and both deploy jobs ran concurrently, or a running
deploy was cancelled by a newer one. The result is a mix of two trees.

**Handling:** serialize deploys with a concurrency group, and **never cancel a running one**.

```yaml
concurrency:
  group: production
  cancel-in-progress: false     # queue; cancelling mid-deploy is the worse outcome
```

`cancel-in-progress: true` is correct for PR checks and wrong for deploys — the same setting, opposite
verdicts, which is why it gets copied into the wrong workflow.

## P17 [Both] — Nobody can say what is running in production

**Root cause:** U3 unmet. Deploys were "whatever was on the branch at the time", with no tag and no
recorded SHA. It surfaces only during an incident, when the rollback target has to be reconstructed
from CI logs under pressure.

**Handling:** record the deployed SHA at deploy time, automatically, whatever the versioning scheme.
The GitFlow ladder gives this away for free via tags; GitHub Flow repos must add it deliberately —
see `github-flow/ci-automation.md`.

## P18 [Both] — Protection is on, but not for the people most able to break it

**Root cause:** `enforce_admins: false`. Branch protection displays as enabled, and the audit box is
ticked, while every admin retains direct push and force-push to `main`. U1, U2, and U4 hold for
everyone except those with the most reach.

**Handling:**

```bash
gh api repos/{owner}/{repo}/branches/main/protection \
  --jq '{admins: .enforce_admins.enabled, force: .allow_force_pushes.enabled, delete: .allow_deletions.enabled}'
```

All three must read `true / false / false`. An emergency bypass, if the org wants one, belongs in a
break-glass procedure that logs and notifies — not in a permanently relaxed rule that nobody
remembers is relaxed.
