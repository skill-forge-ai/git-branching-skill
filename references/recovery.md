# Recovery

Something already went wrong. These are the paths the happy-path lifecycle does not cover — and the
moment an agent is most likely to be invoked, under the most pressure.

**The invariant under threat in every case: `main` describes what is running in production.** Every
other rule is justified by it, and C5 is computed against it. Recovery means restoring that
invariant, not just restoring service.

## Production rollback (single repo)

Restoring service comes first. The branch model question is what happens *after*.

```bash
# fastest path: redeploy the previous final tag. No git surgery under incident.
./deploy.sh v1.3.0
```

Rolling back the **deployment** does not roll back `main`. `main` now claims v1.4.0 is live when
v1.3.0 is. Left alone, this breaks C5 permanently: every future release compares against a `main`
containing code that is not in production, and the gate reports drift that cannot be reconciled.

Pick one, deliberately, and record which:

| Situation | Action |
|---|---|
| **Roll forward** (bug is fixable in hours) | Leave `main` alone. Ship `v1.4.1` through the normal hotfix path. `main` is briefly ahead of production — acceptable, bounded, and the usual case |
| **Roll back for real** (release is withdrawn) | `git revert -m 1 <release-merge-sha>` on `main`, tag `v1.4.1`, deploy it. Production and `main` agree again, and the revert is a recorded decision |

**Never** hard-reset or force-push `main` to the old commit. It breaks every clone, orphans the tag,
and destroys the audit trail of what shipped. Reverting moves forward; resetting rewrites history
others have already built on.

After a real rollback, back-merge the revert to `develop` — otherwise the withdrawn code returns in
the next release, which is the C4 failure with extra steps.

## Abandoning a release

A release that will never ship still holds work and still owns a version number.

**The version number is burned. Do not reuse it.** Under tag-driven deploys, prerelease tags like
`v1.4.0-rc.3` already exist and point at the abandoned code. Reusing `1.4.0` gives one version two
meanings, and any environment that cached the old tag deploys the wrong tree. Next release takes
`1.5.0` (or `1.4.1` if the abandoned work was a feature batch that is no longer shipping).

**The QA fixes on the branch are still valuable, and C4 does not obviously cover this** — the
lifecycle scopes back-merge to "after a production deploy," which never happens here. It still
applies. Recover them before the branch is deleted:

```bash
# what does the abandoned branch have that develop lacks?
git log --oneline --cherry-pick --right-only --no-merges origin/develop...release/1.4.0
```

Cherry-pick the fixes worth keeping into `develop` (not a merge — the version bump commit must not
travel, and the feature work is being abandoned deliberately). Then delete the branch and say in
writing which commits were rescued and which were dropped.

## Two hotfixes racing

`cut-hotfix` fails loudly when `release/x.y.z+1` already exists. That is correct — and this is the
procedure for the human it hands off to.

First determine whether hotfix #1 has reached production:

```bash
git tag --merged origin/main --sort=-v:refname | grep -Ex 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1
```

| State of hotfix #1 | Do this |
|---|---|
| **Not yet deployed**, and both fixes are urgent | Add fix #2 to the *same* carrier `release/x.y.z+1`. They ship together as one version. Couples them — if #1 gets rejected in QA, #2 is stuck behind it — so only do this when both are genuinely urgent |
| **Not yet deployed**, #2 can wait | Queue it. Serialize. This is the AWS "single active release" constraint doing its job |
| **Already deployed** to production | Normal hotfix flow: cut fresh from `main` (which now contains #1), version `x.y.z+2` |

**Never** cut hotfix #2 from `main` while #1 is mid-ladder and expect them to be independent — #2
would not contain #1, and whichever deploys second silently reverts the other. That is P9 arriving
through the hotfix path.

## C5 blocked, and the merge conflicts

The remedy is `git merge --no-ff origin/main`. When that conflicts, you are mid-merge with a
production deploy pending. **This is the highest-risk conflict resolution in the whole model**,
because resolving carelessly toward the release side re-creates the exact missing-content state the
gate just caught.

```bash
git diff --name-only --diff-filter=U        # scope it
git log --merge -p <path>                   # see both sides' intent before choosing
```

Rules while resolving:

- For any file the **hotfix touched**, the production fix must survive. Verify it explicitly after
  resolving — do not assume the merge preserved it:
  ```bash
  git show <hotfix-sha> -- <path>           # what the fix did
  git diff HEAD -- <path>                   # what your resolution kept
  ```
- `--ours` is the release, `--theirs` is `main`. Do not take either wholesale on a file you did not
  write.
- Re-run the gate after resolving. If it is still non-empty, the resolution dropped something.

```bash
git log --oneline --cherry-pick --right-only --no-merges HEAD...origin/main   # must be empty
```

If the conflict cannot be resolved with confidence in the time available, **do not tag**. Ship the
previous version, or ship the hotfix alone from a fresh carrier off `main`. A late release is
recoverable; a production deploy that reverts a live fix is not.

## When `main` and `develop` have permanently diverged

Some content on `main` will never be taken by `develop` — an emergency patch to a file `develop`
deleted, a compliance change scoped to production. Left unreconciled, C5 reports the same
irreconcilable delta on **every** release, which is the P10 death spiral arriving through the correct
gate.

Reconcile once, explicitly: merge `main` into the release (or `develop`) and, in the same merge,
keep the target's content for exactly those paths — then commit it with a message naming the
decision and why. The gate goes quiet truthfully, and the next reader can see the choice was made
rather than forgotten.

Do not solve this by adding an override flag. An override applies to every future release too, and
by then nobody remembers it was scoped to one file.
