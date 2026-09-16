# Detection

Which strategy does this repo actually run? Facts are the agent's job. Read the repo, present the
inference **with its evidence**, ask for confirmation, then cache.

**Do not ask the user questions `git log` already answers. Do not answer from `git log` questions it
cannot settle.** Both failures are common; the second is worse, because a wrong strategy call makes
every downstream instruction wrong in a way that only surfaces at a release.

## Never conclude from these

A strategy is a property of how the repo is *operated*, and none of the following observe that:

- **The repo or org name.** A repo called `gitflow-service` may run GitHub Flow.
- **The language, framework, or hosting.** GitHub-hosted does not imply GitHub Flow.
- **The last repo you worked in.** Peter-style multi-repo work makes this the single most common
  misclassification: assumptions carry over silently.
- **A `CONTRIBUTING.md` that describes a process.** It records what someone intended, possibly years
  ago. Check whether the branches match it; when doc and git disagree, git wins and you say so.
- **One branch name.** A single `develop` proves nothing on its own — see the mixed signals below.

## Procedure

```bash
git fetch origin --tags --prune                        # never detect against a stale remote

git branch -r                                          # integration branch, under any name?
git branch -r --list '*release/*'                      # release branches, current?
git log --all --oneline --diff-filter=A -- . 2>/dev/null >/dev/null  # (no-op; keep fetch above honest)

# historical release branches — they are usually deleted after merging, so the
# live branch list under-reports. Merge commit subjects are the durable record.
git log --oneline --merges origin/main | head -30

git tag --sort=-creatordate | head -40                 # version tags? prerelease channels?
```

Then measure branch lifetime, which is what separates the two models in practice:

```bash
# age of each remote topic branch's first commit that is not on main
for b in $(git branch -r --format='%(refname:short)' | grep -v 'origin/HEAD\|origin/main\|origin/master'); do
  base=$(git merge-base origin/main "$b" 2>/dev/null) || continue
  first=$(git log --reverse --format=%ct "$base".."$b" 2>/dev/null | head -1) || continue
  [ -n "$first" ] && echo "$(( ( $(date +%s) - first ) / 86400 ))d  $b"
done | sort -rn | head -20
```

**Read that output carefully — it over-reports.** It measures age, not lifetime, so a branch that was
merged-and-abandoned but never deleted counts as "old" forever. Before concluding H2 is violated,
separate the two:

```bash
git branch -r --merged origin/main    # already absorbed: age here is just uncollected garbage
git branch -r --no-merged origin/main # genuinely open: THESE are the ages that matter
```

Stale merged branches are a cleanup issue. Old *unmerged* branches are the H2 signal.

Finally read CI config (`.github/workflows/*`, `.gitlab-ci.yml`) for ref→environment routing, and
locate the version source (`package.json`, `pyproject.toml`, `pom.xml`, `Cargo.toml`, or none).

## Signal → conclusion

| Signal | Conclusion |
|---|---|
| Long-lived integration branch **and** `release/*` (live or in merge history) | **GitFlow** |
| Only `main` + topic branches; no `release/*` in history; no integration branch | **GitHub Flow** |
| CI deploys on push/merge to `main` | GitHub Flow evidence (strong) |
| CI deploys on tag push, with prerelease tag patterns | GitFlow evidence (strong) |
| Tags carry `-alpha./-beta./-rc.` | GitFlow, Full profile |
| No version tags at all, deploys keyed to `main` | GitHub Flow |
| Topic branches mostly < 3 days old | GitHub Flow evidence |
| Topic branches routinely > 2 weeks old | Neither is running cleanly — see "long branches" below |
| Repo is new/empty, or has one commit | **No evidence exists. Ask.** |

## The three mixed-signal shapes

These are misclassified more often than either clean case. Each looks like one strategy and is not.

### 1. `develop` exists, but no `release/*` ever did

Check history, not just live branches:

```bash
git log --oneline --merges origin/main | grep -i 'release/' | head
```

Empty means no release branch was ever merged to `main`. The repo is **GitHub Flow with an extra
integration branch** — a staging branch, usually — not GitFlow. Applying G2–G5 here invents a freeze
band nobody operates and a back-merge nobody needs.

**Say so, and ask what `develop` is for.** It is usually one of: a staging deploy target, a stale
leftover, or a half-finished GitFlow adoption. The three have different correct answers.

### 2. `release/*` exists, but there is no integration branch

Usually **version maintenance branches**, not GitFlow freeze bands: `release/1.x` kept alive to patch
an old major while `main` moves on. The tell is lifetime and direction — a GitFlow release branch
lives weeks and merges back; a maintenance branch lives years and receives cherry-picks.

```bash
git log -1 --format='%ci' origin/release/1.x     # still receiving commits after a year?
git log --oneline origin/main..origin/release/1.x | head
```

This is GitHub Flow plus long-term support branches. G5's content gate does not apply between `main`
and a maintenance branch — they are *supposed* to diverge.

### 3. GitFlow branch names, but every branch is months old

Names match GitFlow, operation matches neither. The freeze band is not a freeze band if `develop` is
not taking features meanwhile; the branches are not short-lived either.

**Do not pick a strategy for them.** Report the measurement — branch ages, whether `develop` moved
during the last release, whether back-merges happened — and say that the repo currently runs neither
model cleanly. Then ask which one they intend, because the remediation differs completely:

- Toward GitFlow: start back-merging, enforce the freeze band, add the G5 gate.
- Toward GitHub Flow: split the long branches, adopt flags, shorten the cycle.

## When to ask, and how

**Ask when:** the repo is new or empty, signals conflict, one of the three shapes above is present, or
the user is choosing a strategy rather than following one.

**Do not ask when:** the evidence is clean. Report the conclusion with its evidence and move on.

Present evidence first, inference second, so a wrong guess is correctable at a glance:

```
Detected:
  - Branches: main + 23 topic branches (claude/*, feat/*). No develop, no release/*.
  - Merge history: 180 PR merges into main, none from a release branch.
  - Tags: one non-version tag (pre-rebase-14620855). No vX.Y.Z.
  - CI: test-nextjs.yml runs on PR; deploys are keyed to main via the host.
  - Branch ages: 19 of 23 under 4 days.
Inference: GitHub Flow.
Confirm, or tell me what's wrong?
```

When it is genuinely ambiguous, ask the choice — not the evidence:

```
I can't tell which strategy this repo runs, and the two need opposite advice:
  - `develop` exists (last commit 3 months ago), but no release branch appears
    anywhere in main's merge history.
That shape is usually GitHub Flow with a leftover staging branch, not GitFlow.

Which do you want me to work to?
  1. GitHub Flow — main always deployable, short branches, flags for unfinished work.
  2. GitFlow — I'd need to set up the release-branch process; `develop` is dormant now.
  3. Tell me what `develop` is actually used for and I'll re-infer.
```

For a **new repo with no history**, there is nothing to detect. Ask directly, and give the
one-line version of the trade rather than a lecture — `references/choosing.md` has the decision table
if they want more:

```
New repo, so there's no history to infer from. Two options:
  - GitHub Flow: one main branch, short-lived branches, deploy on merge.
    Suits continuous delivery and small/mature teams.
  - GitFlow: develop + release branches + version tags.
    Suits scheduled releases, multiple supported versions, or compliance sign-off.
Which fits how you ship?
```

## `.git-branching-profile.yml`

A **cache**, not a contract. If the repo drifts, detection wins and the agent says so.

```yaml
# .git-branching-profile.yml
strategy: github-flow          # gitflow | github-flow
detected: 2026-09-16
confirmed_by: user             # user | inference

branches:                      # actual names in THIS repo, not the canonical ones
  main: main                   # may be `master`
  integration: null            # `develop` / `dev` / `integration`; null in GitHub Flow
  release_prefix: null         # `release/`; null in GitHub Flow

# --- GitFlow only ---
profile: null                  # full | lean | merged-staging
versioning:
  carrier: tag                 # tag | branch
  source: package.json         # or null when tag-only
  bump_on_cut: true
channels: []                   # [alpha, beta, rc]; [] when none

# --- GitHub Flow only ---
deploy:
  trigger: merge-to-main       # merge-to-main | tag | manual
  marks_release: auto-tag      # auto-tag | manual-tag | sha-only  (U3 must be satisfied)
feature_flags:
  system: null                 # e.g. LaunchDarkly, env var, DB table; null = none yet
  required_for_unfinished: true

gates:
  pr_required: true            # U2
  content_check: true          # GitFlow G5 only; ignore in GitHub Flow

toggles:
  joint_release: false
  ci_automation: true
```

`content_check` has no `false` that the agent should honor silently **in a GitFlow repo** — hotfixes
alone guarantee `main` moves independently of any release branch. In a GitHub Flow repo the field is
not applicable, and its absence is not a gap.

`feature_flags.system: null` in a GitHub Flow repo is a **real gap worth reporting** — H3 has no
mechanism behind it, which is how long-lived branches creep back in.
