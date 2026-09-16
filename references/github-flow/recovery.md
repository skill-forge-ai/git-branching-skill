# GitHub Flow recovery

Something already went wrong. This is the moment an agent is most likely to be invoked, under the
most pressure, and the moment U4 is most likely to be violated "just this once."

**The invariant under threat: `main` is always deployable.** Recovery means restoring that, not just
restoring service — those are two separate tasks and the second one does not imply the first.

**The GitFlow reflex to suppress:** there is no freeze band to retreat to. Do not cut a release branch
mid-incident. Inventing an untested process while production is down is how a 10-minute incident
becomes an hour.

## Restore service first, decide the git question second

These are separate, and conflating them costs time in both directions — people do git surgery while
users are down, or they fix the outage and never fix `main`.

```bash
# fastest path: redeploy the last known-good artifact. No git surgery under incident.
./deploy.sh "$(git describe --tags --abbrev=0 HEAD^)"   # or whatever names the previous deploy
```

This is why U3 exists. A team that cannot name the previous deploy has no fast path here and must
debug under pressure instead.

**Redeploying an old artifact does not change `main`.** `main` still contains the bad commit and is
still what the next merge builds on. Until you deal with it, the next person to deploy re-ships the
outage.

## A bad commit reached `main`

Pick one deliberately. The choice is about time-to-fix, not about taste.

| Situation | Action |
|---|---|
| **Cause understood, fix is small and obvious** (< ~15 min, low risk) | Roll forward: a normal hotfix branch, PR, gate, deploy |
| **Cause unclear, or the fix is not obvious** | `git revert` the merge, deploy, then debug at leisure on a branch |
| **The change is behind a flag** | Turn the flag off. No deploy, no git operation. This is what flags are for |
| **Several merges landed since, and the bad one is entangled** | Revert what you can isolate; if you cannot, roll forward. Do not unpick history |

Reverting is the default when uncertain. It is bounded, reviewable, and reversible; authoring a fix
under pressure is none of those.

```bash
# revert a squash-merged PR (one commit on main)
git revert <sha>

# revert a true merge commit — -m 1 keeps main's side as the mainline
git revert -m 1 <merge-sha>
```

Then take it through the normal gate. **A revert is a change to `main` and gets a PR like any other**
(U2) — it is the change most likely to be wrong in a hurry, not least likely.

**Never** hard-reset or force-push `main` to the last good commit (U4). It breaks every clone,
orphans the deployment record, and destroys the evidence of what shipped — which you will want during
the postmortem.

### Re-landing reverted work

The reverted commit is still in history, so simply merging the branch again lands nothing: git sees
the content as already present and then absent by decision.

```bash
git revert <the-revert-sha>       # undo the undo, then fix forward on top
```

Do this on a fresh branch with the actual fix in the same PR. A bare revert-of-revert re-ships the
original bug.

## `main` is red and everyone is blocked

`main`'s own CI failing is an H1 violation in progress: nobody can honestly merge, because nobody can
claim `main` is deployable.

**Treat it as a stop-the-line event.** The usual mistake is merging around it — each additional merge
makes the bisect harder and buries the cause.

```bash
# what landed since the last green run?
gh run list --branch main --limit 20
git log --oneline <last-green-sha>..origin/main
```

| Cause | Action |
|---|---|
| A specific merge broke it | Revert that merge. Fastest, and it restores everyone else |
| Flaky test, confirmed flaky | Quarantine the test in its own PR, with an owner and a date. Not a `|| true` |
| External dependency broke (registry, base image) | Pin or vendor it; note that CI green now depends on something outside the repo |
| Nobody knows | Revert to the last green and debug on a branch. Do not leave `main` red while investigating |

A "temporarily" disabled required check is how a gate becomes permanently advisory. If you disable
one, put the re-enable in the same conversation with a name attached.

## The flag kill switch

When work is behind a flag, most of this document does not apply — and that is the argument for H3.

```
Flag off → behaviour reverts → no deploy, no git operation, seconds not minutes
```

Two failure modes that make a flag *not* a kill switch, both worth checking before relying on one:

- **The flag is read once at startup.** Turning it off then requires a restart, which is a deploy with
  extra steps. Read flags per-request, or accept that it is not an instant switch.
- **The flagged path wrote data the unflagged path cannot read.** Turning the flag off strands or
  corrupts that data. Any flag near a schema or a write path needs the off-state to be tested, not
  assumed.

**Test the off path.** A flag nobody has turned off since the launch is an untested rollback.

## When the deploy succeeded but the release was wrong

Service is fine; the wrong thing shipped — a premature feature, a partial migration, a legal or
pricing change. No CI signal fires here, so it is found by a human and arrives as "undo it now."

Same decision as above, with one addition: **check whether it wrote anything.** Reverting code does
not revert rows written while it was live. Establish what state was created before reverting, or the
revert leaves data no code path understands.

```bash
git log --oneline <deploy-tag>..origin/main -- migrations/ db/
```

## Postmortem inputs the branching model owes you

If these cannot be answered from the repo, the gap is in U1–U3, not in people's memory:

- **What was live when it broke?** → the deploy tag/SHA (U3)
- **What changed between the last good deploy and that one?** → `git log <prev-tag>..<tag>`
- **Who reviewed it?** → the PR (U2)
- **How long was it live before detection?** → deploy timestamps

A team that answers these from Slack scrollback has an invariant to fix before it has a process to
fix.
