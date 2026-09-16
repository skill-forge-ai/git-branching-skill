# GitHub Flow CI automation

In GitFlow, CI's job is to move an artifact along a ladder of environments. Here CI's job is simpler
and stricter: **be the gate that makes "`main` is always deployable" true**, then deploy and record
what it deployed.

> **Platform status.** The GitHub Actions examples below are written against Actions semantics and
> the failure modes noted inline are real (the `GITHUB_TOKEN` one in particular). They have not been
> run end to end in every configuration — treat them as a starting point, not battle-tested config.

## Jobs

| Job | Trigger | Does |
|---|---|---|
| `pr-gate` | every PR to `main` | build, test, lint — **required**, blocking |
| `deploy` | push to `main` | deploy, then record what was deployed |
| `tag-deploy` | after a successful deploy | create the immutable reference (U3) |
| `flag-audit` | scheduled | report flags older than N days (H3 stage 5) |
| `stale-branches` | scheduled | report unmerged branches older than N days (H2) |

The last two are reporting, not enforcement. They exist because H2 and H3 decay silently — nothing
fails when a flag lingers or a branch ages, which is exactly why both need something that looks.

## The gate is the whole safety net

In GitFlow, a release branch gives you a second chance to catch a bad merge. Here there is no second
chance: merged means deployable. So the gate's job is not to report — it is to **block**.

Three ways a gate stops being a gate, all of which look green:

1. **The check is not marked required.** It runs, it fails, the merge button stays enabled.
2. **The author can dismiss the review or approve their own PR.** U2 satisfied on paper only.
3. **The check only runs on the branch, not on the merge result.** Branch passed against a stale
   `main`; the merged state was never tested. GitHub's "require branches to be up to date" closes
   this — at the cost of a re-run per merge.

Verify rather than assume:

```bash
gh api repos/{owner}/{repo}/branches/main/protection --jq '{
  required_checks: .required_status_checks.contexts,
  strict_up_to_date: .required_status_checks.strict,
  reviews: .required_pull_request_reviews.required_approving_review_count,
  dismiss_stale: .required_pull_request_reviews.dismiss_stale_reviews,
  enforce_admins: .enforce_admins.enabled,
  force_push: .allow_force_pushes.enabled
}'
```

`enforce_admins: false` means U1 and U2 hold for everyone except the people most able to cause a bad
day. `allow_force_pushes: true` means U4 is unenforced.

## PR gate

```yaml
name: pr-gate
on:
  pull_request:
    branches: [main]

concurrency:                         # cancel superseded runs on the same PR
  group: pr-${{ github.ref }}
  cancel-in-progress: true

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '22', cache: npm }
      - run: npm ci
      - run: npm run typecheck
      - run: npm test
      - run: npm run lint
```

`pull_request` builds the **merge result**, not the branch tip — which is what you want, and differs
from `push`. Combined with "require branches to be up to date", it closes gap 3 above.

**Name the job stably.** The branch-protection rule references it by name; renaming the job silently
removes the requirement and the merge button goes green. This is a real and quiet failure — grep the
protection config whenever a job is renamed.

## Deploy on merge, then record

```yaml
name: deploy
on:
  push:
    branches: [main]

concurrency:                         # never let two deploys race
  group: production
  cancel-in-progress: false          # queue them; do NOT cancel a running deploy

permissions:
  contents: write                    # needed to push the tag

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production          # approval gate, if the team wants one
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - run: ./deploy.sh
      - name: Record what was deployed (U3)
        run: |
          TAG="deploy-$(date -u +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)"
          git tag -a "$TAG" -m "Deployed to production"
          git push origin "$TAG"
```

**`cancel-in-progress: false` on the production group.** Cancelling a running deploy leaves
production in a state that matches no commit — the one outcome worse than deploying serially.

**`environment: production` is where an approval gate goes** if merging and deploying should be
separate decisions. Note the trade: an approval here widens the merge→deploy window, during which
`main` is ahead of production. Keep the queue short or the window becomes the norm.

### The tag-push trap

A tag pushed with the default `GITHUB_TOKEN` **does not trigger other workflows**. This is deliberate
(loop prevention) and silent. If anything downstream keys off the deploy tag — release notes, a
notification, a dependent repo — it will not run and nothing will say so.

Use a PAT or `repository_dispatch` when a downstream workflow must fire. If the tag is only a record,
`GITHUB_TOKEN` is correct and simpler.

## Decay reports

Nothing fails when H2 and H3 erode, so something has to look on purpose.

```yaml
name: hygiene
on:
  schedule: [{ cron: '0 9 * * 1' }]   # Monday morning
  workflow_dispatch:

jobs:
  stale-branches:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: Unmerged branches older than 14 days (H2)
        run: |
          git fetch origin --prune
          for b in $(git branch -r --no-merged origin/main --format='%(refname:short)' \
                     | grep -v 'origin/HEAD'); do
            base=$(git merge-base origin/main "$b") || continue
            first=$(git log --reverse --format=%ct "$base".."$b" | head -1) || continue
            [ -n "$first" ] || continue
            age=$(( ( $(date +%s) - first ) / 86400 ))
            [ "$age" -gt 14 ] && echo "${age}d  $b"
          done | sort -rn
```

`--no-merged` is the important half: merged-but-undeleted branches are cleanup noise, not an H2
signal, and mixing them in makes the report ignorable within two weeks.

For flags, the equivalent is a grep over the flag registry with a creation date. The specific
mechanism varies; **the requirement is that some scheduled thing names flags past their removal
date**, because nobody volunteers to delete a flag that is working.

## What NOT to build

Automation that contradicts the model, all of which teams reach for:

| Tempting | Why not |
|---|---|
| A `release/*` job "for big launches" | You are running GitFlow for one release without its back-merge or content gate. Change the repo's strategy deliberately (`../choosing.md`) or use a flag |
| An override that merges past a red gate | The gate is the entire safety net (H1). An override that exists gets used, then gets used routinely |
| Auto-merge on green with no review | U2. Green means the tests that exist passed — it does not mean anyone understood the change |
| Force-push protection disabled "for rebases" | U4. Rebase topic branches freely; `main` is not a topic branch |
| A "revert" job that resets `main` and force-pushes | U4, and it destroys the deployment record exactly when the postmortem needs it. Revert commits, never reset |
