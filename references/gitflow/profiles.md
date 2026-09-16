# GitFlow profiles

## Detection

Strategy detection (GitFlow vs GitHub Flow) lives in [`../detection.md`](../detection.md). **Read that
first** — this file only distinguishes the three GitFlow *profiles*, and applies once the repo is
already known to run GitFlow.

Profile signals, after GitFlow is established:

| Signal | Conclusion |
|---|---|
| Tags carry `-alpha./-beta./-rc.` | Prerelease ladder present → Full |
| Only bare `vX.Y.Z` tags, release branches exist | No prerelease channels → Lean |
| CI deploys `develop` to a preprod-grade environment | `develop` doubles as staging → Merged-staging |
| Every deploy job is automatic, none `manual` / `environment:` | Approval gates off |
| Version string in code matches recent tags | Version lives in code → a bump step exists |
| Version in code is static (e.g. `0.0.1`) while tags advance | Tag-only versioning → **no bump step** |

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

A repo with no release branch is not a broken GitFlow repo — it is **GitHub Flow**, and this file
does not apply to it. Switch to [`../github-flow/`](../github-flow/lifecycle.md) and the H-rules in
SKILL.md.

Do not operate GitFlow rules on a trunk-based repo. The advice would be wrong in ways that only
surface at a release. If the team is *choosing* between the two rather than following one, see
[`../choosing.md`](../choosing.md).

## Profile cache

A **cache**, not a contract. If the repo drifts, detection wins and the agent says so.

```yaml
# .git-branching-profile.yml (GitFlow section)
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
  content_check: true          # G5 — content check, never ancestry

toggles:
  joint_release: false
  ci_automation: true
```

These keys live in the shared `.git-branching-profile.yml` (schema in [`../detection.md`](../detection.md)).

`content_check` has no `false` that the agent should honor silently. G5 applies to every profile —
hotfixes alone guarantee `main` moves independently of any release branch. If a project sets it
false, report it as a gap rather than complying.
