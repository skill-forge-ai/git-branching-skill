# Choosing between them, and migrating

For an existing repo, **detect first** (`detection.md`). This file is for a new repo, a deliberate
change, or a team that has drifted into running neither model cleanly.

## The actual question

Not "which is better" — AWS is careful to frame both as fit-for-purpose. The question is:

> **Where do you put unfinished work while it is unfinished — in a branch, or behind a flag?**

Every other difference follows. GitFlow answers "in a branch" and then needs release branches,
back-merges, and a content gate to keep those branches from losing each other's work. GitHub Flow
answers "behind a flag" and then needs `main` to be permanently deployable, which needs a gate that
blocks and branches that do not live long enough to diverge.

**The failure mode is answering neither.** Long-lived branches with no freeze band and no flags is
the most common real-world state, and it is worse than either model run properly: GitFlow's merge
pain without its protection, GitHub Flow's exposure without its speed.

## Decision table

| If this is true | Lean | Why |
|---|---|---|
| You deploy several times a week or on merge | **GitHub Flow** | A freeze band you cut and merge daily is pure overhead |
| You ship on a schedule (monthly, quarterly, to a customer window) | **GitFlow** | The freeze band is exactly the stabilization period you already have |
| You must support more than one released version at a time | **GitFlow** | GitHub Flow has no answer for "patch 2.3 while 3.0 is live" |
| A release needs sign-off (compliance, audit, regulated change control) | **GitFlow** | AWS: GitHub Flow "is not well suited if your teams have strict compliance or release processes to follow" |
| You cannot turn features off at runtime, and won't build that | **GitFlow** | H3 has no mechanism; GitHub Flow will degrade into long branches |
| Customers pull your release (mobile app store, on-prem, SDK) | **GitFlow** | You genuinely have releases as objects, not just deploys |
| Small team, strong review culture, continuous delivery | **GitHub Flow** | AWS: "well suited for smaller, mature, development teams that have strong communication skills" |
| You are a web service and deploy is entirely yours | **GitHub Flow** | Nothing needs a version number to exist |
| Your team is new to git or distributed across time zones with light review | **GitFlow** | Merge conflicts are "common in this model and will likely happen often" (AWS); GitFlow's structure absorbs weaker communication |

**Two or three rows decide it.** If rows split evenly, the tiebreak is the flag question above — a
team that will not build a flag mechanism should not choose GitHub Flow, regardless of cadence.

## Honest costs

Neither is free. Choose the bill you would rather pay.

| | GitFlow costs | GitHub Flow costs |
|---|---|---|
| Ongoing | Release-branch bookkeeping; mandatory back-merges; a content gate that must be implemented correctly (G5) | Flag discipline including removal; frequent small merges; conflict resolution as a routine skill |
| When skipped | Lost hotfixes, silent reverts in production (P8, P9) | Long-lived branches return; `main` stops being deployable; you have neither model |
| Learning curve | Higher. More branch types, more rules, more to get wrong | Lower to start, but the flag discipline is a real engineering practice, not a convention |
| Worst day | The release that silently reverted a live hotfix | The bad merge that is already in production |

## Not a third strategy: the deviations that are actually fine

Two common deviations look like drift and are not, provided they are deliberate and written down:

**GitHub Flow + long-term support branches.** `main` runs GitHub Flow; `release/1.x` exists to patch
an old major for customers still on it. This is not GitFlow — there is no freeze band and no
back-merge obligation — and G5 does not apply between `main` and a maintenance branch, because they
are *supposed* to diverge. What it does need: a written rule on which fixes get backported, and
cherry-picks going one direction only (`main` → maintenance, never back).

**GitFlow without prerelease channels.** Covered as the Lean profile (`gitflow/profiles.md`). Release
branches and the G-rules still apply; only the tag ladder is absent.

What is *not* fine is cutting a release branch for one launch in an otherwise GitHub Flow repo. You
inherit GitFlow's divergence with none of its machinery, and the first hotfix during that launch is
the P9 scenario with no gate to catch it.

## Migrating GitFlow → GitHub Flow

Usually driven by "releases take too long" or "the back-merge is always broken." Order matters —
**the flags come first.** Removing the freeze band before you can hide unfinished work is how a team
ends up with an undeployable `main`.

1. **Build the flag mechanism and use it once**, on a real feature, before changing any branches.
   Without this, step 4 cannot hold.
2. **Make the PR gate blocking on `main`.** Required checks, required review, no self-approval,
   `enforce_admins` on. In GitFlow the release branch absorbed mistakes; nothing will now.
3. **Finish the in-flight release the old way.** Do not convert mid-ladder; tag it, deploy it,
   back-merge it.
4. **Retire `develop`.** Merge it into `main` (no squash), verify nothing is left behind, then
   protect `main` as the only long-lived branch:
   ```bash
   git log --oneline --cherry-pick --right-only --no-merges origin/main...origin/develop
   # must be empty before you delete develop
   ```
5. **Shorten branches deliberately.** Split anything open and large; this is where the flag work pays
   off.
6. **Set up the deploy record** (U3) — GitFlow gave you version tags for free, and nothing replaces
   them automatically.

**Reversible until step 4.** Keep `develop` until the gate and the flags have survived a real
release.

## Migrating GitHub Flow → GitFlow

Usually driven by a new compliance requirement, a customer-facing version, or supporting an old
release. The order is the reverse insight — **the gate comes last**, because G5 cannot be implemented
until there is something to compare.

1. **Create `develop` from `main`** and point CI's non-production deploys at it.
2. **Re-point topic branches**: features now cut from and merge to `develop`.
3. **Agree the version scheme before the first cut**, not during it. Retrofitting SemVer onto a repo
   with deploy-timestamp tags is a naming migration nobody enjoys mid-release.
4. **Cut the first `release/*` and walk the whole lifecycle** — including the back-merge to both
   branches, even though the first one is nearly a no-op. The habit is the point.
5. **Implement the G5 gate** (`gitflow/ci-automation.md`) — and implement it correctly the first
   time. A gate that fires on every healthy release trains the team to bypass it before it has ever
   protected anything (P10 → P9).
6. **Write down the hotfix path** and rehearse it once. `hotfix/*` cuts from `main`, never `develop`
   (G4) — this is the rule a team arriving from GitHub Flow breaks first, because there `main` was
   the only branch.

**The cultural change is larger than the mechanical one.** "Merged" stops meaning "shipping soon,"
and unfinished work goes back into branches. Teams that keep merging to `develop` at GitHub Flow
cadence while treating release branches as ceremony get GitFlow's overhead and none of its
stabilization.
