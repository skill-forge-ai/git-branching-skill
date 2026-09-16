# GitHub Flow lifecycle

Step-by-step procedures with per-step verification. The AWS pattern is the reference model; where
common practice diverges, the divergence is named.

**The whole model in one sentence:** cut from `main`, keep it short, merge through a gate that
actually blocks, deploy, and name what you deployed.

## Ordering rule

**Merge → deploy → mark.** In GitFlow the tag precedes the merge, because `main` must equal
production. Here `main` leads production by design — it is what production is *about to be* — so the
order inverts.

The consequence teams miss: between merge and deploy there is a window where `main` is ahead of
production. Keep it short (deploy on merge) or make it visible (a deployment record, an environment
page). A long unexamined window is how "main is always deployable" quietly becomes false.

## The standard flow

AWS's sequence, with the verification each step needs:

```bash
# 1. Cut from the remote ref, never a stale local main
git fetch origin --prune
git checkout -b feature/1234_pm_export_csv origin/main
```

Naming follows `<type>/<ticket>_<initials>_<descriptor>`. The type prefix is for tracking and
priority only — `feature`, `bugfix`, and `hotfix` have identical mechanics here. That is the point of
the model.

```bash
# 2. Commit in small, discrete steps
git commit -am "Add CSV column mapping for export"
git push -u origin feature/1234_pm_export_csv
```

```bash
# 3. Open the PR early — it is the review and CI surface, not a completion announcement
gh pr create --fill
```

Opening early is what makes H5 cheap: the branch is visible, and conflicts surface while they are
still small.

```bash
# 4. Keep it current while it is open (H5)
git fetch origin && git merge origin/main
```

**Do this on a cadence, not once at the end.** AWS states it as the model's primary troubleshooting
item: *"We recommend that you frequently merge changes from `main` into lower branches to avoid
significant conflicts when you merge to `main`."*

Merge or rebase is a team choice; merging is safer on a shared branch, rebasing keeps history linear
on a solo branch. **Never rebase a branch someone else has pulled** without agreeing first.

```bash
# 5. Merge through the gate
gh pr merge --squash
```

Squash is the common default here and is safe: in GitHub Flow every merge is topic → long-lived,
which is exactly the direction GitFlow's G3 permits. There are no long-lived-to-long-lived merges to
get wrong.

**The gate must actually block.** A required check that can be dismissed by the author, or a review
requirement that the author can self-satisfy, is not a gate. This is the entire safety net (H1) —
verify the branch protection rather than assuming it:

```bash
gh api repos/{owner}/{repo}/branches/main/protection \
  --jq '{reviews: .required_pull_request_reviews, checks: .required_status_checks.contexts, force: .allow_force_pushes.enabled}'
```

```bash
# 6. Deploy, then mark what was deployed (U3)
git fetch origin --tags
git tag -a "v$(date +%Y.%m.%d)-$(git rev-parse --short origin/main)" origin/main -m "Deployed to production"
git push origin --tags
```

Any scheme works — SemVer, CalVer, or a deployment record in the CD system — as long as **the live
commit is nameable afterwards and the previous one is still deployable.** "Deploy whatever is on
`main`" fails this: by the time you look, `main` has moved.

```bash
# 7. Delete the merged branch
git push origin --delete feature/1234_pm_export_csv
```

Not housekeeping. Undeleted merged branches are what makes the H2 lifetime measurement unreadable
(`references/detection.md`).

## Hotfix

AWS is explicit that there is no separate mechanism: *"`Hotfix` branches, which are akin to `feature`
or `bugfix` branches, can follow the same process as either of these other branches. However, given
their urgency, hotfixes typically have a higher priority."*

```bash
git fetch origin --prune
git checkout -b hotfix/5678_pm_payment_null origin/main
# fix, commit, push, PR
gh pr create --fill --label urgent
```

**What may be compressed:** review latency (page a reviewer instead of waiting), the size of the
change, the number of approvals if policy allows a documented lower bar for incidents.

**What may not:** the PR itself (U2), the gate's automated checks, and naming what you deployed (U3).
Those are the three things you need most when the hotfix itself turns out to be wrong.

Decide the compressed path **before** the incident and write it down. A team improvising "can we skip
review this once" at 2am reliably skips the wrong thing.

**If `main` is broken right now**, the fix is not always forward — see `recovery.md`. Reverting the
bad commit is usually faster and always safer than authoring a fix under pressure.

## Feature flags (H3)

The load-bearing half of GitHub Flow, and the part most often skipped. Without it, H1 and H2 cannot
both hold: work that takes two weeks either sits on a branch for two weeks (violating H2) or reaches
`main` unfinished and undeployable (violating H1).

The flag lifecycle:

| Stage | State | Merged to `main`? |
|---|---|---|
| 1. Add the flag, default off | Code ships dark, no behaviour change | Yes, immediately |
| 2. Build behind it | Each PR is small and independently safe | Yes, continuously |
| 3. Enable for a subset | Internal users, then a percentage | Already there |
| 4. Enable for everyone | The launch | Already there |
| 5. **Remove the flag and the old path** | Scheduled work, not "someday" | Yes |

**Stage 5 is not optional and does not happen on its own.** Flags that outlive their launch become
permanent untested branches in the code — the same combinatorial problem as long-lived git branches,
moved into runtime where it is harder to see. Put removal on the board when the flag is created.

A flag that gates a database migration or an external side effect is not a flag; it is a deploy
ordering problem wearing a flag's clothes. Those need the migration to be safe in both states
(expand/contract), not a boolean.

**Minimum viable flag system:** an environment variable per feature and a documented list of what is
currently on. Named systems (LaunchDarkly and friends) buy targeting and audit, not the core
capability. A repo with no flag mechanism at all should record that as a gap — it is the mechanism H3
rests on.

## Marking releases without release branches

GitHub Flow has "no explicit release process" (AWS lists this under disadvantages). Teams that need
release *artifacts* — release notes, a version to quote in a support ticket, an audit record — get
them from tags and the deployment history instead of from branches.

| Need | GitHub Flow answer |
|---|---|
| "What is in production?" | The tag or SHA recorded at deploy (U3) |
| "What changed since the last deploy?" | `git log --oneline <last-deploy-tag>..origin/main` |
| Release notes | Generate from merged PR titles between the two tags |
| "Roll back to last known good" | Redeploy the previous tag's artifact; see `recovery.md` |
| Support an old version for a customer | This is the case GitHub Flow does not serve. A maintenance branch is a real deviation — decide it deliberately (`../choosing.md`) |

```bash
# what is about to ship, or what just shipped
git log --oneline --no-merges "$(git describe --tags --abbrev=0)"..origin/main
```

## Verification checklist

Before saying the flow is healthy, check the things that silently stop being true:

```bash
# H1: does main actually pass its own gate right now?
gh run list --branch main --limit 5

# H2: genuinely open branches, oldest first
git branch -r --no-merged origin/main

# U2/H1: is the gate real, or advisory?
gh api repos/{owner}/{repo}/branches/main/protection --jq '.required_status_checks.contexts'

# U3: can you name what is live?
git tag --sort=-creatordate | head -5
```

A green CI badge on a PR says the branch passed **at merge time**. H1 is a claim about `main` *now*,
after everyone else's merges — which is why the first check reads `main`'s own runs, not the PRs'.
