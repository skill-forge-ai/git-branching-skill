# Profiles and detection

## Detection procedure

Facts are the agent's job. Read the repo, present the inference **with its evidence**, ask for
confirmation, then cache. Do not ask the user questions `git log` already answers.

```bash
git fetch origin --tags --prune

git branch -r                                     # develop present? (C1)
git branch -r --list '*release/*'                 # release branches cut? (C2)
git log --oneline --merges origin/main | head -20 # historical release merges
git tag --sort=-creatordate | head -40            # channels: -alpha. -beta. -rc.
```

Then read CI config (`.gitlab-ci.yml`, `.github/workflows/*`) for ref→environment routing and
approval gates, and locate the version source (`pyproject.toml`, `package.json`, `pom.xml`,
`Cargo.toml`, or none — tag-only).

### Signal → conclusion

| Signal | Conclusion |
|---|---|
| No long-lived integration branch under any name (`develop`, `dev`, `development`, `integration`) | C1 violated — not GitFlow. Stop and say so. Check aliases before concluding this |
| No `release/*`, current or historical | C2 violated — GitHub Flow. Offer the two honest exits |
| Tags carry `-alpha./-beta./-rc.` | Prerelease ladder present → Full |
| Only bare `vX.Y.Z` tags, release branches exist | No prerelease channels → Lean |
| CI deploys `develop` to a preprod-grade environment | `develop` doubles as staging → Merged-staging |
| Every deploy job is automatic, none `manual` / `environment:` | Approval gates off |
| Version string in code matches recent tags | Version lives in code → a bump step exists |
| Version in code is static (e.g. `0.0.1`) while tags advance | Tag-only versioning → **no bump step** |

### Present it like this

```
Detected:
  - `develop` exists, 40 commits ahead of `main`
  - 12 release merge commits in main's history, latest `release/1.4.0`
  - Recent tags: v1.4.0, v1.4.0-rc.1, v1.4.0-alpha.0 → full prerelease ladder
  - CI: develop→dev (auto), -alpha|-rc→test-staging (auto), vX.Y.Z→prod (manual)
Inference: Full profile, tag-driven, prod gated.
Confirm, or tell me what's wrong?
```

Evidence first, inference second — so a wrong guess is correctable at a glance.

## The three profiles

| | Full | Lean | Merged-staging |
|---|---|---|---|
| Environments | dev / test-staging / prod | dev / prod | `develop` *is* staging / prod |
| Prerelease channels | `alpha.N → beta.N → rc.N` | none | rc only, or none |
| Release branch | yes, lives through the ladder | yes, short | yes |
| Final tag gate | rc acceptance | release CI green + human confirm | rc or human confirm |
| QA shift-left | recommended | recommended | **mandatory** — no other gate |

Toggles, orthogonal to profile: prerelease channels, approval gates, joint multi-repo release, CI
automation, bump-on-cut.

### Why Merged-staging makes shift-left mandatory

With `develop` serving as staging, there is no downstream environment where QA can catch what
`develop` missed. The premise that made shift-left merely *advisable* — a separate test environment
after it — is gone, so the rule promotes to mandatory. This is the premise mechanism working: the
rule changes because its precondition changed, not because a table says so.

## Not GitFlow

A repo with no release branch violates C2. That is GitHub Flow. Say it plainly and offer:

1. **Adopt a release branch** — gains the freeze band: `develop` keeps moving while a release
   stabilizes.
2. **Keep trunk-based and call it GitHub Flow** — legitimate, especially with continuous deployment
   and strong feature flags. AWS itself says GitFlow suits teams that need release guardrails, not
   teams pursuing continuous delivery.

Do not quietly operate a GitFlow skill on a trunk-based repo. The advice would be wrong in ways that
only surface at the release.

## `.gitflow-profile.yml`

A **cache**, not a contract. If the repo drifts, detection wins and the agent says so.

```yaml
# .gitflow-profile.yml
profile: full                  # full | lean | merged-staging
detected: 2026-08-10

branches:                      # actual names in THIS repo, not the canonical ones.
  main: main                   # may be `master`
  develop: develop             # may be `dev` / `development` / `integration`
  release_prefix: release/

versioning:
  carrier: tag                 # tag | branch
  source: pyproject.toml       # or null when tag-only
  bump_on_cut: true

channels: [alpha, beta, rc]    # [] when none

environments:
  develop: dev
  prerelease: test-staging
  final: prod

gates:
  prod_approval: manual
  content_check: true          # C5 — file diff, never ancestry

toggles:
  joint_release: false
  ci_automation: true
```

`content_check` has no `false` that the agent should honor silently. C5 applies to every profile —
hotfixes alone guarantee `main` moves independently of any release branch. If a project sets it
false, report it as a gap rather than complying.
