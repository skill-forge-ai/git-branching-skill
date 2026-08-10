# AWS baseline, and where practice diverges

Source: AWS Prescriptive Guidance — *Implement a GitFlow branching strategy for multi-account DevOps
environments* and *Choosing a Git branching approach*. This file separates what AWS actually says
from what teams commonly adapt, so an adaptation is a decision rather than a drift.

## The AWS model

| Branch | Cut from | Merges into | Naming |
|---|---|---|---|
| `feature` | `develop` | `develop` (**squash**) | `feature/<ticket>_<initials>_<desc>` |
| `develop` | — (long-lived, protected) | release branches cut from it | `develop` |
| `release` | `develop` | **both** `main` and `develop` after prod deploy, fast-forward, **never squash** | `release/v{major}.{minor}` |
| `main` | — (long-lived, protected) | receives release merges | `main` |
| `bugfix` | the `release` branch | that release branch (**squash**) | `bugfix/<ticket>_<initials>_<desc>` |
| `hotfix` | **`main`** | a `release` branch cut from `main` (**squash**) — never straight to `main` | `hotfix/<ticket>_<initials>_<desc>` |

Five environments: **Sandbox → Development → Testing → Staging → Production**, one or more AWS
accounts each. Branches map to environments, not to accounts.

**Two ideas the model rests on:**

1. **Build once, deploy many.** The release branch build publishes artifacts that are promoted
   through test → stage → prod. Each promotion is a manual approval.
2. **Merge back as soon as possible**, to both `main` and `develop`, after the production deploy.

**Rules AWS states as troubleshooting**, easy to miss and load-bearing:

- *"We recommend that you have only a single release branch active at a time."* More than one and
  environment changes collide.
- *"Only use a squash merge when you are merging from a feature branch to a develop branch."*
  Squashing higher branches makes merging back down difficult.
- *"Releases should be merged back into main and develop as soon as possible."*

AWS also scopes the model honestly: suited to larger distributed teams with strict release and
compliance requirements; explicitly **not** suited to organizations pursuing continuous delivery,
"due to the rigid nature of managing release branches."

## Common divergences

| Dimension | AWS | Common practice | Why |
|---|---|---|---|
| Environments | 5 | 3, with test and staging sharing one cluster | Cost. Small teams cannot staff or fund five |
| Version carrier | **release branch name**; git tags never mentioned | git **tags**, with tag push as the deploy trigger | Tags are immutable, orderable, and cheap; one branch can carry a whole ladder |
| Version granularity | `major.minor` only, no patch | full SemVer with patch | Hotfixes need a patch component |
| Prerelease stages | none — promotion is approval-gated only | `-alpha.N / -beta.N / -rc.N` encoding environment state | With shared environments, the tag suffix is what routes the deploy |
| Sandbox branches | `sandbox/*` for pipeline testing | usually dropped | Ephemeral preview environments cover it |

**The tag shift is the consequential one.** Once tags drive deploys, AWS's guidance that release
branches carry versions no longer maps cleanly, and a whole class of rules appears that AWS never
needed: anchored tag patterns (P5), protected-variable visibility (P7), immutability of a bad final
tag. Adopt tag-driven deploys and you inherit those.

## What is preserved regardless

Every adaptation here keeps: the branch model's shape, hotfix-from-`main`, mandatory back-merge to
both long-lived branches, the squash direction rule, and merging only after a successful production
deploy. Those are C1–C4.

**C5 — the content gate — is not in AWS.** AWS never states it because its model never needs it: with
release branches as version carriers and no tag-triggered deploys, "does this release contain
production's content" is answered structurally. Once tags trigger deploys from a branch that may have
drifted, the check becomes necessary — so adopting tag-driven deploys means adding a rule AWS's text
does not supply.

Teams reach it independently, and the usual path there is instructive: implement it as
`merge-base --is-ancestor`, watch it fire on every healthy release, then switch to comparing content.
That second step is the right instinct, but the obvious content check —
`git diff HEAD...origin/main` — is a three-dot diff, which expands to
`git diff $(git merge-base HEAD main) main` and never reads the release side at all. It passes a
release that inherited a hotfix and then removed it. The check that holds is the one in SKILL.md C5:
`git log --cherry-pick --right-only`, which asks which of main's commits the release never received.

## Constraints that relax, and why

AWS's "single active release branch" is a consequence of *shared environments*, not of GitFlow
itself. Given per-release ephemeral environments, parallel releases are safe. This is the general
pattern: an AWS rule that looks absolute is usually downstream of an infrastructure assumption. Find
the assumption before discarding — or keeping — the rule.

C1–C5 are the exception. They do not relax under any infrastructure.
