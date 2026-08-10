# gitflow-skill

An agent skill for GitFlow: branch model, release lifecycle, and the checks that keep production from
silently losing work. Built on the AWS Prescriptive Guidance GitFlow model, adapted for tag-driven
deploys, and hardened against the failure modes that show up in real pipelines.

It adapts to the repo in front of it — full prerelease ladder, no prerelease channels, or `develop`
doubling as staging — while refusing to bend on five rules.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/skill-forge-ai/gitflow-skill/main/install.sh | bash
```

Auto-detects Claude Code, Codex, or Cursor. To be explicit:

```bash
AGENT=codex          curl -fsSL .../install.sh | bash    # ~/.codex/skills
INSTALL_DIR=/somewhere curl -fsSL .../install.sh | bash  # anywhere
```

Or clone and copy `SKILL.md` + `references/` into your agent's skills directory. There is nothing to
build.

## What it covers

| | |
|---|---|
| `SKILL.md` | Five non-negotiable rules, the C5 content gate, rationalizations, branch-choice table, detection, lifecycle |
| `references/lifecycle.md` | Release, hotfix, bugfix, back-merge — step by step with verification |
| `references/ci-automation.md` | One-click CI: `cut-release`, `cut-hotfix`, promotion, mergeback. GitLab CI and GitHub Actions |
| `references/recovery.md` | Production rollback, abandoned release, racing hotfixes, C5 merge conflicts |
| `references/pitfalls.md` | Ten field-collected failures: symptom, root cause, handling |
| `references/profiles.md` | Detection signals, three profiles, `.gitflow-profile.yml` schema |
| `references/joint-release.md` | Multi-repo coupling, deploy ordering, rollback asymmetry |
| `references/aws-baseline.md` | The AWS model, and where practice diverges from it |

## The part worth reading even if you skip the rest

Before tagging a release for production, verify the release branch contains everything already live.
Two intuitive implementations of that check are wrong:

```bash
# ✗ ancestry — fails on every healthy release after a --no-ff back-merge,
#   so the team learns to bypass it, and it protects nothing when drift is real
git merge-base --is-ancestor origin/main HEAD

# ✗ three-dot diff — expands to `git diff $(git merge-base HEAD main) main`.
#   It compares the merge base to main and never reads the release side, so it
#   passes a release that inherited a hotfix and then dropped it
git diff HEAD...origin/main
```

```bash
# ✓ which of main's commits did this release never receive?
git fetch origin +refs/heads/main:refs/remotes/origin/main
git log --oneline --cherry-pick --right-only --no-merges HEAD...origin/main
```

`--cherry-pick` compares by patch-id, so a fix the release obtained another way (cherry-pick,
independent re-application) is correctly treated as present. Every claim above was verified in scratch
repositories, not reasoned about.

## Development

```bash
./scripts/check-install.sh     # install.sh file list matches the repo layout
```

## License

MIT
