---
name: gitflow
description: Use when cutting or tagging a release, shipping a hotfix, merging back to develop or main, deciding whether a fix belongs on develop or the active release branch, or identifying and adopting a repo's branching strategy (GitFlow vs GitHub Flow / trunk-based). Also when a release gate fails or someone wants to override it, a shipped feature or hotfix went missing after a release, a tag pipeline did not run, a prerelease tag reached production, or several repos must ship together. Covers release/*, hotfix/*, back-merge, vX.Y.Z, -rc.N, code freeze.
---

# GitFlow

Branch model, release lifecycle, and the checks that keep production from silently losing work.
Adapts to the project in front of you; refuses to bend on five rules.

**Core principle:** a release branch is a code-freeze isolation band. Everything else follows from
protecting what is in production while `develop` keeps moving.

## The hard core (refuse, don't adapt)

Violating the letter of these is violating the spirit of these. When a project's practice breaks one,
say so, explain the specific loss, and do not proceed as-asked.

| # | Rule | What breaks |
|---|---|---|
| C1 | `main` and `develop` both long-lived and protected | No stable answer to "what is in production" |
| C2 | `release/*` is a freeze band — after the cut, `develop` keeps taking features | Without it this is trunk-based, and release work blocks all other work |
| C3 | Squash **topic → long-lived** only (`feature`→`develop`, `bugfix`/`hotfix`→`release`). **Never** between long-lived branches (`release`→`main`/`develop`) | Squash records no merge, so the merge base never advances; every later merge recomputes against the old base, replaying resolved conflicts and able to revert live work |
| C4 | Back-merge is mandatory; `hotfix/*` cuts from `main`, never `develop` | Production fixes get overwritten by the next release |
| C5 | Before a final tag, the release must contain all of `main`'s **content** — checked by file diff, never by ancestry | The prod deploy silently reverts hotfixes that shipped mid-ladder |

C5 is where agents reliably fail. Read the next section before implementing any release gate.

## C5: check content, not ancestry

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

On non-empty output: merge `main` → `release/*` (**no squash**, C3), re-run CI, then tag. Never force
past it. Tags are immutable — a bad final tag is fixed by moving forward, not deleting.

**What this gate cannot see.** If the release *received* main's commit and a later commit changed
that code, nothing is missing from git's view — it is an ordinary divergent edit, indistinguishable
from intended work. The gate catches commits that never arrived, which is the hotfix-lost case. It
does not police intent; review does.

## Rationalizations

| Claim | Reality |
|---|---|
| "`--is-ancestor` has no false-positive mode" | It has a common one: any release cut from `develop` after a `--no-ff` back-merge, because the merge commit stays on `main` while only its content reaches `develop`. Not universal — it passes when the back-merge fast-forwarded, or the branch was cut from `main` — so "it passed once" is no evidence the check is sound. Precise about ancestry, wrong question for completeness |
| "The gate fails every release — known false positive, here's the override" | Half right. It IS a false positive; the fix is replacing the check, not overriding it. Overriding leaves you unprotected against the real case |
| "Gate always fails ⇒ the team skips back-merges" | Plausible and usually wrong. Run the correct check before blaming anyone — the usual cause is the gate asking the wrong question |
| "Squash collapses 47 conflicts into one resolution" | Same content, resolved once, then replayed on every future merge with no per-commit context |
| "Everything in release came from develop, so back-merge is a no-op" | Release branches accumulate commits never on develop: QA fixes, version bump, and any hotfix merged in from main |
| "One-line fix, just push to main" | Unbranched fixes can't propagate; they vanish at the next release |
| "Branch off develop, the related fix is already there" | Ships every untested commit on develop to production |

## Getting past a gate legitimately

A gate with no lawful exit gets deleted or `|| true`'d. There is no override flag; there are
procedures that make the gate green **truthfully**.

| Situation | Procedure |
|---|---|
| Main has a hotfix the team has decided to **revert** | Merge `main` in (no squash), then `git revert` the hotfix on the release branch. The removal is recorded as a decision rather than an absence, and the gate goes green |
| Main and develop have **permanently diverged** (main carries something develop will never take) | Reconcile once with a recorded merge that keeps the release's side for those paths, so the gate stops reporting the same unfixable delta every release |
| Gate is failing and you cannot tell why | Do not tag. `git log --oneline --cherry-pick --right-only --no-merges HEAD...origin/main` names the exact commits; inspect them before deciding |

If you are about to argue the gate does not apply this once, that is the P10 pattern — see
`references/pitfalls.md`.

**Already gone wrong** — production rolled back, release abandoned, two hotfixes racing, or the C5
merge conflicts: `references/recovery.md`. Do not improvise these; each one has a way to make things
worse, and rollback in particular breaks the `main = production` invariant every other rule rests on.

## Which branch does this fix belong on?

| | Bugfix | Hotfix |
|---|---|---|
| Fixes | a release not yet in production | code live in production |
| Cut from | the active `release/*` | `main` |
| Merges into | that release branch (squash) | its own `release/x.y.z+1` carrier (squash) |
| Version | none | PATCH+1 |

**When an active release branch exists, its fixes target it, not `develop`** — otherwise the fix
never reaches the environment under test. Check first: `git branch -r --list '*release/*'`.

## Adapt to the project

Detect, show evidence, confirm, cache. Never ask what `git log` already answers.

```bash
git fetch origin --tags --prune                # never detect against a stale remote
git branch -r                                  # integration branch present? (C1)
git branch -r --list '*release/*'              # are release branches cut? (C2)
git tag --sort=-creatordate | head -40         # -alpha./-beta./-rc. channels?
```

**Match the role, not the literal name.** The integration branch may be `develop`, `dev`,
`development`, or `integration`; the production branch may be `main` or `master`. C1 is about a
long-lived integration branch existing — do not halt on a healthy repo because it named it `dev`.
Record the actual names in the profile and use them throughout.

Then read CI config for ref→environment routing, and the version source. Present the inference **with
evidence**, ask to confirm, cache to `.gitflow-profile.yml`. If the repo later drifts from the cache,
detection wins — say so rather than following a stale file.

Three profiles — **Full** (prerelease ladder), **Lean** (no prerelease channels), **Merged-staging**
(`develop` *is* staging). Definitions, signal→conclusion table, and schema: `references/profiles.md`.

**No release branch at all?** That violates C2 — it is GitHub Flow, not GitFlow. Say so and offer the
two honest options: adopt a release branch, or keep trunk-based and call it GitHub Flow.

**Conditional rules carry their premise**, so a cut-down setup can be reasoned about rather than
looked up — e.g. "one active release" exists because test and staging share a cluster, and relaxes
when they don't; QA shift-left is advisory only while a separate test environment exists downstream,
and becomes mandatory without one. Full table in `references/profiles.md`.

C1–C5 have no such escape. C5 applies to every profile: hotfixes alone guarantee `main` moves
independently of any release branch.

## Lifecycle

```
feature/* ──squash──▶ develop ──cut──▶ release/x.y.z
                         ▲                  ├─ prerelease tags ──▶ test envs
                         │                  ├─ bugfix/* ──squash──▶ (re-tag)
                         │                  └─ C5 gate ─▶ final tag ─▶ PROD (gated)
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

## Red flags — stop

- About to override, delete, or `|| true` a release gate
- About to squash anything into `main` or `develop`
- Cutting a hotfix from `develop`
- Deleting a release branch before the back-merge lands
- Tagging while the C5 check names commits the release never received
- Explaining why this project is the exception to C1–C5

## References

- `references/profiles.md` — detection rules, three profiles, `.gitflow-profile.yml` schema
- `references/lifecycle.md` — step-by-step release, hotfix, bugfix, back-merge with verification
- `references/ci-automation.md` — one-click CI: `cut-release`, `cut-hotfix`, promotion, mergeback
- `references/recovery.md` — production rollback, abandoned release, racing hotfixes, C5 merge conflict
- `references/pitfalls.md` — symptom / root cause / handling
- `references/joint-release.md` — multi-repo coupling, deploy ordering
- `references/aws-baseline.md` — AWS model and where common adaptations diverge
