---
name: git-branching
description: Use when identifying or adopting a repo's branching strategy (GitFlow vs GitHub Flow vs trunk-based), cutting or tagging a release, shipping a hotfix, merging back to develop or main, deciding whether a fix belongs on develop or the active release branch, or opening a PR into a protected main. Also when a release gate fails or someone wants to override it, a shipped feature or hotfix went missing after a release, a tag pipeline did not run, a prerelease tag reached production, a bad commit reached main, long-lived branches are causing repeated merge conflicts, or several repos must ship together. Covers release/*, hotfix/*, back-merge, vX.Y.Z, -rc.N, code freeze, feature flags, PR gates, revert-and-roll-forward.
---

# Git branching

Two strategies, one skill. Detect which one the repo actually runs, then apply that strategy's rules —
never the other's.

**The most expensive mistake this skill exists to prevent is applying GitFlow's rules to a GitHub Flow
repo, or the reverse.** They are not two dialects of one model. They make opposite trades, and each
one's safety net is the thing the other deliberately removes.

| | GitFlow | GitHub Flow |
|---|---|---|
| Protects releases with | a `release/*` freeze band | `main` always being deployable |
| Hides unfinished work in | a branch | a feature flag |
| Recovers from a bad release by | holding it in the freeze band | reverting on `main` and rolling forward |
| Costs you | release-branch bookkeeping, back-merges | flag discipline, merge-conflict frequency |

Pick one deliberately. Running half of each gives you neither safety net — see
`references/choosing.md`.

## Start here: which strategy is this repo running?

**Never assume from the repo name, the language, or the last repo you worked in.** Detect, show the
evidence, and when the evidence is ambiguous or the repo is new, **ask — do not guess.**

```bash
git fetch origin --tags --prune                # never detect against a stale remote
git branch -r                                  # long-lived integration branch?
git branch -r --list '*release/*'              # release branches, current or historical?
git log --oneline --merges origin/main | head -20
git tag --sort=-creatordate | head -40
```

| Evidence | Conclusion |
|---|---|
| Long-lived integration branch (`develop`/`dev`/`integration`) **and** `release/*`, current or historical | **GitFlow** → this file's G-rules, `references/gitflow/` |
| Only `main` plus short-lived topic branches; no `release/*`, no integration branch | **GitHub Flow** → this file's H-rules, `references/github-flow/` |
| Signals conflict, or the repo is new/empty | **Ask the user.** Present what you saw, then offer the choice |

Full procedure, the ambiguous shapes that are routinely misread, and the exact question to ask:
`references/detection.md`. **Read it before concluding anything** — the three mixed-signal shapes
there are misclassified more often than either clean case.

Cache the answer in `.git-branching-profile.yml`; if the repo later drifts from the cache, detection
wins and you say so.

## U — universal invariants (both strategies)

Violating these is not a strategy choice; it is an absent strategy.

| # | Rule | What breaks without it |
|---|---|---|
| U1 | The production branch (`main`/`master`) is long-lived and protected — no direct pushes, no deletion | Nothing answers "what is in production", and any push can become a release |
| U2 | Every change reaches the production branch through a reviewed PR/MR | Unreviewed code ships; the audit trail has holes exactly where it matters |
| U3 | Whatever is deployed to production is identifiable by an immutable reference (a tag, or a recorded SHA) and the previous one is still deployable | You cannot answer "what is live" or "roll it back" under incident pressure |
| U4 | The production branch moves forward only — `revert`, never force-push or hard reset | Force-pushing `main` breaks every clone, orphans tags, and destroys the record of what shipped |

U3 is the one teams skip. "Deploy whatever is on `main` right now" satisfies nobody at 3am: by the
time you look, `main` has moved. Record the SHA at deploy time even when you do not tag.

## G — GitFlow invariants

**Apply only to a repo detected or declared as GitFlow.** In a GitHub Flow repo these are not
violated — they are irrelevant, and citing them is the misapplication this skill exists to prevent.

**Core principle:** a release branch is a code-freeze isolation band. Everything else follows from
protecting what is in production while `develop` keeps moving.

| # | Rule | What breaks |
|---|---|---|
| G1 | `main` and `develop` both long-lived and protected | No stable answer to "what is in production" |
| G2 | `release/*` is a freeze band — after the cut, `develop` keeps taking features | Without it this is trunk-based, and release work blocks all other work |
| G3 | Squash **topic → long-lived** only (`feature`→`develop`, `bugfix`/`hotfix`→`release`). **Never** between long-lived branches (`release`→`main`/`develop`) | Squash records no merge, so the merge base never advances; every later merge recomputes against the old base, replaying resolved conflicts and able to revert live work |
| G4 | Back-merge is mandatory; `hotfix/*` cuts from `main`, never `develop` | Production fixes get overwritten by the next release |
| G5 | Before a final tag, the release must contain all of `main`'s **content** — checked by commit reachability, never by ancestry | The prod deploy silently reverts hotfixes that shipped mid-ladder |

G5 is where agents reliably fail. Read the next section before implementing any release gate.

### G5: check content, not ancestry

**The intuitive implementation is wrong and fires on every healthy release:**

```bash
git merge-base --is-ancestor origin/main HEAD   # ✗ WRONG — permanent false positive
```

Back-merge carries main's **content** into `develop`; the merge commit itself stays on `main`. So a
release later cut from `develop` is complete but never has main's tip as an ancestor. The gate fails
forever, everyone learns to bypass it, and it protects nothing on the day it matters.

**Ask which of main's commits the release never received:**

```bash
git fetch origin +refs/heads/main:refs/remotes/origin/main   # explicit refspec: plain
                                                             # `git fetch origin main` writes
                                                             # FETCH_HEAD, may leave origin/main stale
git log --oneline --cherry-pick --right-only --no-merges HEAD...origin/main
# empty = release has every main-side change → safe to tag
```

`--cherry-pick` drops commits whose patch already exists on the release side, so it stays quiet when
the release obtained the same fix by another route (cherry-pick, independent re-application). That is
why it beats a plain file diff, which blocks in that case.

**Do not use `git diff HEAD...origin/main` for this.** Three-dot diff means
`git diff $(git merge-base HEAD main) main` — it compares the *merge base* to main and never looks at
the release side at all. It reports what main changed, not what the release lacks, so it both blocks
healthy releases and passes releases that dropped main's content after inheriting it.

On non-empty output: merge `main` → `release/*` (**no squash**, G3), re-run CI, then tag. Never force
past it. Tags are immutable — a bad final tag is fixed by moving forward, not deleting.

**What this gate cannot see.** If the release *received* main's commit and a later commit changed
that code, nothing is missing from git's view — it is an ordinary divergent edit, indistinguishable
from intended work. The gate catches commits that never arrived, which is the hotfix-lost case. It
does not police intent; review does.

### GitFlow rationalizations

| Claim | Reality |
|---|---|
| "`--is-ancestor` has no false-positive mode" | It has a common one: any release cut from `develop` after a `--no-ff` back-merge, because the merge commit stays on `main` while only its content reaches `develop`. Not universal — it passes when the back-merge fast-forwarded, or the branch was cut from `main` — so "it passed once" is no evidence the check is sound. Precise about ancestry, wrong question for completeness |
| "The gate fails every release — known false positive, here's the override" | Half right. It IS a false positive; the fix is replacing the check, not overriding it. Overriding leaves you unprotected against the real case |
| "Gate always fails ⇒ the team skips back-merges" | Plausible and usually wrong. Run the correct check before blaming anyone — the usual cause is the gate asking the wrong question |
| "Squash collapses 47 conflicts into one resolution" | Same content, resolved once, then replayed on every future merge with no per-commit context |
| "Everything in release came from develop, so back-merge is a no-op" | Release branches accumulate commits never on develop: QA fixes, version bump, and any hotfix merged in from main |
| "One-line fix, just push to main" | Unbranched fixes can't propagate; they vanish at the next release |
| "Branch off develop, the related fix is already there" | Ships every untested commit on develop to production |

### Getting past a GitFlow gate legitimately

A gate with no lawful exit gets deleted or `|| true`'d. There is no override flag; there are
procedures that make the gate green **truthfully**.

| Situation | Procedure |
|---|---|
| Main has a hotfix the team has decided to **revert** | Merge `main` in (no squash), then `git revert` the hotfix on the release branch. The removal is recorded as a decision rather than an absence, and the gate goes green |
| Main and develop have **permanently diverged** (main carries something develop will never take) | Reconcile once with a recorded merge that keeps the release's side for those paths, so the gate stops reporting the same unfixable delta every release |
| Gate is failing and you cannot tell why | Do not tag. `git log --oneline --cherry-pick --right-only --no-merges HEAD...origin/main` names the exact commits; inspect them before deciding |

If you are about to argue the gate does not apply this once, that is the P10 pattern — see
`references/pitfalls.md`.

### Which branch does this GitFlow fix belong on?

| | Bugfix | Hotfix |
|---|---|---|
| Fixes | a release not yet in production | code live in production |
| Cut from | the active `release/*` | `main` |
| Merges into | that release branch (squash) | its own `release/x.y.z+1` carrier (squash) |
| Version | none | PATCH+1 |

**When an active release branch exists, its fixes target it, not `develop`** — otherwise the fix
never reaches the environment under test. Check first: `git branch -r --list '*release/*'`.

### GitFlow lifecycle

```
feature/* ──squash──▶ develop ──cut──▶ release/x.y.z
                         ▲                  ├─ prerelease tags ──▶ test envs
                         │                  ├─ bugfix/* ──squash──▶ (re-tag)
                         │                  └─ G5 gate ─▶ final tag ─▶ PROD (gated)
                         │                                    │
                         └──── back-merge ◀───── merge ◀──────┴──▶ main
                                (no squash)                        (no squash)
```

Tag on the release branch → deploy prod → **then** merge to `main` and `develop`. Merging first makes
`main` contain unshipped code, breaking "main = production".

**Hotfix cuts two branches from `main`:** `hotfix/<ticket>` for the fix, and `release/x.y.z+1` as the
carrier. Squash the hotfix into the carrier, then it traverses the normal gates. The carrier exists so
one branch type owns environment traversal — gates, promotion, and mergeback are all written against
`release/*`. Same shape as a release, PATCH increment, compressed rounds — not a shortcut past the
environments.

Three profiles — **Full** (prerelease ladder), **Lean** (no prerelease channels), **Merged-staging**
(`develop` *is* staging). Definitions and schema: `references/gitflow/profiles.md`. Step-by-step
procedures: `references/gitflow/lifecycle.md`.

**Conditional rules carry their premise**, so a cut-down setup can be reasoned about rather than
looked up — e.g. "one active release" exists because test and staging share a cluster, and relaxes
when they don't; QA shift-left is advisory only while a separate test environment exists downstream,
and becomes mandatory without one.

G1–G5 have no such escape. G5 applies to every profile: hotfixes alone guarantee `main` moves
independently of any release branch.

## H — GitHub Flow invariants

**Apply only to a repo detected or declared as GitHub Flow.** The absence of `release/*` here is the
design, not a defect — do not report it as a violation.

**Core principle:** `main` is always deployable, so the thing that protects production is the gate in
front of the merge, not a branch behind it.

| # | Rule | What breaks |
|---|---|---|
| H1 | `main` is always deployable. Merging is the act of saying "this can go to production" | The one safety net GitHub Flow has. Without it you have trunk-based development with no trunk discipline |
| H2 | Topic branches are short-lived — hours to a couple of days | Long branches ARE release branches without the freeze-band rules. You get GitFlow's conflicts and none of its protection |
| H3 | Unfinished work is hidden behind a feature flag, never behind a long-lived branch | H1 and H2 cannot both hold otherwise. This is the trade GitFlow makes with branches; skipping it is how teams get the worst of both |
| H4 | Recovery is roll-forward: `revert` on `main`, then deploy. There is no freeze band to fall back to | Reaching for a release branch mid-incident invents an untested process at the worst moment |
| H5 | Merge `main` into open topic branches frequently | AWS names this the model's most common failure: conflicts compound until the merge back to `main` is unsafe |

**H2 and H3 are one rule in two halves, and the most misunderstood part of GitHub Flow.** The model
is not "GitFlow with fewer rules." It moves the isolation of unfinished work out of branches and into
flags. A team that adopts the smaller rulebook without adopting flags ends up with long-lived
branches *and* no freeze band — strictly worse than either strategy run properly.

### GitHub Flow rationalizations

| Claim | Reality |
|---|---|
| "No release branch means fewer rules, so this is the easy option" | The rules moved, they did not disappear. Flag discipline, short branches, and a merge gate that actually blocks are load-bearing. AWS: "It is not well suited if your teams have strict compliance or release processes to follow" |
| "This branch is big, so keep it open until the feature is done" | That is a release branch with no freeze-band rules. Split the work, merge it behind a flag, and keep `main` deployable |
| "We'll cut a release branch just for this one big launch" | Then you are running GitFlow for one release, without its back-merge or content gate. Decide the strategy at the repo level, not per-feature |
| "`main` broke, roll back by force-pushing to the last good commit" | U4. Revert and roll forward; force-pushing `main` breaks every clone and orphans the record of what shipped |
| "Hotfixes need their own process" | In GitHub Flow a hotfix is an ordinary branch off `main` with the review expedited. AWS: "while the hotfix process parallels the feature or bugfix process, the urgency surrounding hotfixes may warrant modifications in the procedural adherence" |
| "We deploy on merge, so tagging is pointless" | U3. Something must name what is live and what to go back to. Auto-tag on deploy if nobody wants to tag by hand |

### GitHub Flow lifecycle

```
              ┌──── merge main in frequently (H5) ────┐
              ▼                                       │
main ──cut──▶ feature/* ──PR + gate──▶ main ──▶ deploy ──▶ tag/record SHA (U3)
 ▲            (short-lived, H2)         │
 │            unfinished work           │
 │            behind a flag (H3)        │
 └──────────── revert + roll forward ◀──┘  (H4)
```

Every branch type — `feature/*`, `bugfix/*`, `hotfix/*` — cuts from `main` and merges back to `main`.
The names are for tracking and priority, not for different mechanics. Step-by-step procedures,
including the flag lifecycle and what to do when a bad commit reaches `main`:
`references/github-flow/lifecycle.md` and `references/github-flow/recovery.md`.

## Red flags — stop

**Both strategies:**

- About to force-push, hard-reset, or delete the production branch (U4)
- About to push to `main` without a PR, "just this once" (U2)
- Deploying something you cannot name afterwards — no tag, no recorded SHA (U3)
- Applying G-rules in a GitHub Flow repo, or H-rules in a GitFlow repo
- Concluding a strategy from the repo's name, framework, or the last repo you touched, rather than from `git`

**GitFlow only:**

- About to override, delete, or `|| true` a release gate
- About to squash anything into `main` or `develop`
- Cutting a hotfix from `develop`
- Deleting a release branch before the back-merge lands
- Tagging while the G5 check names commits the release never received
- Explaining why this project is the exception to G1–G5

**GitHub Flow only:**

- A topic branch older than a few days with no plan to split it (H2)
- Cutting a release branch "just for this launch" without switching the whole repo to GitFlow
- Merging something to `main` that nobody intends to deploy (H1)
- Building a rollback plan that depends on a branch rather than a revert (H4)

## References

**Both strategies:**

- `references/detection.md` — detection procedure, mixed-signal shapes, how to ask, profile cache schema
- `references/choosing.md` — choosing between the two, and migrating from one to the other
- `references/pitfalls.md` — symptom / root cause / handling, tagged by strategy
- `references/aws-baseline.md` — the AWS models for both, and where practice diverges
- `references/handbook-zh.md` — 中文手册，写给不写代码、通过 agent 操作 git 的人

**GitFlow:**

- `references/gitflow/profiles.md` — the three profiles and their premises
- `references/gitflow/lifecycle.md` — release, hotfix, bugfix, back-merge with verification
- `references/gitflow/ci-automation.md` — one-click CI: `cut-release`, `cut-hotfix`, promotion, mergeback
- `references/gitflow/recovery.md` — production rollback, abandoned release, racing hotfixes, G5 merge conflict
- `references/gitflow/joint-release.md` — multi-repo coupling, deploy ordering

**GitHub Flow:**

- `references/github-flow/lifecycle.md` — daily flow, hotfix, feature flags, release marking
- `references/github-flow/ci-automation.md` — PR gates, deploy-on-merge, tagging, flag cleanup
- `references/github-flow/recovery.md` — bad commit on main, revert vs roll-forward, flag kill switch
