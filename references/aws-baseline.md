# AWS baseline, and where practice diverges

Source: AWS Prescriptive Guidance — *Choosing a Git branching approach for multi-account DevOps
environments*, plus the two implementation patterns (*Implement a GitFlow branching strategy* and
*Implement a GitHub Flow branching strategy*). This file separates what AWS actually says from what
teams commonly adapt, so an adaptation is a decision rather than a drift.

AWS documents both strategies in the same series, with the same five environments and the same
Punnett-square diagram format — branches on one axis, environments on the other. That framing is
useful: **the strategies differ in which branch occupies each column, not in what the environments
are for.**

## The AWS GitFlow model

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
deploy. Those are G1–G4.

**G5 — the content gate — is not in AWS.** AWS never states it because its model never needs it: with
release branches as version carriers and no tag-triggered deploys, "does this release contain
production's content" is answered structurally. Once tags trigger deploys from a branch that may have
drifted, the check becomes necessary — so adopting tag-driven deploys means adding a rule AWS's text
does not supply.

Teams reach it independently, and the usual path there is instructive: implement it as
`merge-base --is-ancestor`, watch it fire on every healthy release, then switch to comparing content.
That second step is the right instinct, but the obvious content check —
`git diff HEAD...origin/main` — is a three-dot diff, which expands to
`git diff $(git merge-base HEAD main) main` and never reads the release side at all. It passes a
release that inherited a hotfix and then removed it. The check that holds is the one in SKILL.md G5:
`git log --cherry-pick --right-only`, which asks which of main's commits the release never received.

## Constraints that relax, and why

AWS's "single active release branch" is a consequence of *shared environments*, not of GitFlow
itself. Given per-release ephemeral environments, parallel releases are safe. This is the general
pattern: an AWS rule that looks absolute is usually downstream of an infrastructure assumption. Find
the assumption before discarding — or keeping — the rule.

G1–G5 are the exception. They do not relax under any infrastructure.

---

# The AWS GitHub Flow model

Source: *Implement a GitHub Flow branching strategy for multi-account DevOps environments* and
*Branches in a GitHub Flow strategy*.

| Branch | Cut from | Merges into | Naming |
|---|---|---|---|
| `feature` | `main` | `main` via merge request | `feature/<story number>_<initials>_<descriptor>` |
| `bugfix` | `main` | `main` via merge request | `bugfix/<ticket number>_<initials>_<descriptor>` |
| `hotfix` | `main` | `main` via merge request | `hotfix/<ticket number>_<initials>_<descriptor>` |
| `main` | — (long-lived, protected) | — | `main` |

**All three topic types are the same mechanism.** AWS says so directly for both `bugfix` and
`hotfix`: *"This is a suggested naming convention for organization and tracking, this process could
also be managed using a feature branch."* The prefix carries priority and traceability, not
different rules.

On `main`: *"The `main` branch always represents the code that is running in production. … To protect
against deletion and to prevent developers from pushing code directly to `main`, enable branch
protection for the `main` branch."* That is U1 and U2 stated as product guidance.

## The standard workflow, as AWS numbers it

Same five environments as GitFlow — Sandbox → Development → Testing → Staging → Production — but the
promotion unit is a merge request rather than a release branch:

1. Developer creates a `feature` branch from `main` in the sandbox environment.
2. Commits are added, each a discrete change.
3. A merge request to `main` opens, initiating review.
4. Reviewers discuss and give feedback.
5. **Opening the MR triggers an automated build and deploys the branch to the development
   environment.**
6. Automated tests run; *"A successful build, successful deployment, and successful testing are
   required to complete the merge request."*
7. On review completion, changes merge to `main`.
8–10. An approver manually approves deployment of the release artifacts to testing, then staging,
then production.

**Step 6 is the gate, and AWS makes it a completion requirement rather than a report.** That is H1's
enforcement mechanism in the AWS phrasing.

**Steps 8–10 are worth noticing**, because they are frequently dropped in practice. AWS's GitHub Flow
still has manual approval at each environment promotion — it is not "merge equals production." Teams
that deploy straight to production on merge have made a further adaptation, and it is a real one:
they have traded the approval gates for deploy frequency, and the PR gate is then genuinely the only
check.

## What AWS says about fit

Unusually direct, and worth quoting when a team is choosing:

> "The Github Flow branching strategy is well suited for smaller, mature, development teams that have
> strong communication skills. This strategy is well suited to teams that want to implement continuous
> delivery… **It is not well suited if your teams have strict compliance or release processes to
> follow.** Merge conflicts are common in this model and will likely happen often. Resolution of merge
> conflicts is a key skill, and you must train all team members accordingly."

The disadvantages AWS lists map directly onto this skill's H-rules:

| AWS disadvantage | Rule that addresses it |
|---|---|
| "Lack of formal release structure… does not explicitly define a release process or support features such as versioning, hotfixes, or maintenance branches" | U3 — mark deploys even without release branches |
| "Limited suitability for large projects… multiple long-term feature branches" | H2 — and the honest answer is that this case wants GitFlow |
| "Potential for frequent merge conflicts" | H5 — merge `main` in frequently |
| "Impact of breaking changes… higher risk of introducing breaking changes" | H1 plus a gate that blocks |
| "Lack of formalized workflow phases… no alpha, beta, or release candidate stages" | Accepted trade; flags provide staged exposure instead |

AWS's troubleshooting section names two issues. The first is the branch-conflict case that H5
answers. The second is **team maturity**: *"It is imperative that the team has the engineering
maturity to build features and create automation tests for them. The team must perform an exhaustive
merge request review before changes are approved."*

That is the honest precondition. GitHub Flow's smaller rulebook is not a smaller commitment — it
relocates the commitment from process to engineering practice.

## Where practice diverges from AWS's GitHub Flow

| Dimension | AWS | Common practice | Why |
|---|---|---|---|
| Environments | 5, with manual approval at each promotion | 2–3, deploy on merge to production | Continuous delivery; the approval gates are what teams drop first |
| Feature flags | not mentioned | central to the model | Without them, H1 and H2 cannot both hold — AWS's "every feature branch is deployable at any time" implicitly assumes small features |
| Versioning | not addressed | deploy tags (CalVer, SHA-stamped) or a CD deployment record | U3 has to come from somewhere once release branches are gone |
| Merge style | "merge request", style unspecified | squash-merge by default | Every merge here is topic → long-lived, the direction GitFlow's G3 also permits |
| Hotfix | same process, expedited | same, plus a pre-agreed compressed review path | Deciding the compressed path during an incident is how the wrong step gets skipped |

**The feature-flag gap is the consequential one.** AWS states the model's premise — *"The key is that
every `feature` branch is deployable at any time"* — without naming the mechanism that makes it
achievable for work larger than a day. Adopt GitHub Flow without flags and that premise quietly
becomes false, which is P13.
