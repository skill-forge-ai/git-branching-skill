# git-branching-skill

An agent skill for Git branching strategy: **GitFlow and GitHub Flow**, the release lifecycle each
one implies, and the checks that keep production from silently losing work.

It detects which strategy the repo in front of it actually runs, applies that strategy's rules, and
**asks rather than guesses** when the evidence is ambiguous or the repo is new.

> Previously published as `gitflow`. The skill now installs as `git-branching`; the repository URL is
> unchanged.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/skill-forge-ai/gitflow-skill/main/install.sh | bash
```

Auto-detects Claude Code, Codex, or Cursor. To be explicit:

```bash
AGENT=codex            curl -fsSL .../install.sh | bash    # ~/.codex/skills
INSTALL_DIR=/somewhere curl -fsSL .../install.sh | bash    # anywhere
```

Or clone and copy `SKILL.md` + `references/` into your agent's skills directory. There is nothing to
build. If you installed the older `gitflow` skill, remove that directory after installing this one.

## The idea

The two strategies are not dialects of one model. **Each one's safety net is the thing the other
deliberately removes**, so applying one's rules to the other's repo is the expensive mistake this
skill exists to prevent.

| | GitFlow | GitHub Flow |
|---|---|---|
| Protects releases with | a `release/*` freeze band | `main` always being deployable |
| Hides unfinished work in | a branch | a feature flag |
| Recovers from a bad release by | holding it in the freeze band | reverting on `main` and rolling forward |
| Costs you | release-branch bookkeeping, back-merges | flag discipline, merge-conflict frequency |

Rules are therefore layered: **U1–U4** hold everywhere, **G1–G5** apply only to GitFlow repos, and
**H1–H5** only to GitHub Flow repos. A GitHub Flow repo having no release branch is the design, not a
violation to report.

## What it covers

| | |
|---|---|
| `SKILL.md` | Layered invariants (U/G/H), detection entry point, both lifecycles, red flags |
| `references/detection.md` | Detection procedure, the three mixed-signal shapes, how to ask, profile cache |
| `references/choosing.md` | Choosing between the two, honest costs, migrating either direction |
| `references/pitfalls.md` | 18 field-collected failures, tagged by strategy |
| `references/aws-baseline.md` | The AWS models for both strategies, and where practice diverges |
| `references/handbook-zh.md` | 中文手册，写给通过 agent 操作 git 的非技术人员 |
| `references/gitflow/` | Lifecycle, CI automation, recovery, profiles, joint release |
| `references/github-flow/` | Lifecycle, PR gates and deploy-on-merge, recovery |

## The part worth reading even if you skip the rest

**GitFlow — before tagging a release for production, verify the release branch contains everything
already live.** Two intuitive implementations of that check are wrong:

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
independent re-application) is correctly treated as present.

**GitHub Flow — the gate is the entire safety net, and it fails silently.** Branch protection
references a required check *by job name*; rename the job and the rule now requires something that
never reports, while the merge button turns green:

```bash
gh api repos/{owner}/{repo}/branches/main/protection --jq '.required_status_checks.contexts[]' | sort > /tmp/required
gh pr view <recent-pr> --json statusCheckRollup \
  --jq '.statusCheckRollup[] | (.name // .context)' | sort -u > /tmp/reported
comm -23 /tmp/required /tmp/reported     # non-empty = required but never reports = main is open
```

Also check `enforce_admins` — protection that exempts admins leaves U1, U2 and U4 unenforced for the
people with the most reach.

## Development

```bash
./scripts/check-install.sh     # install.sh file list matches the repo layout
```

## License

MIT
