# Joint release (multi-repo)

When several services ship together. AWS's model does not cover this — it assumes one repo per
pipeline — so this is adaptation, not doctrine.

**Off by default.** Only engage when the user says multiple repos ship together.

## Each repo runs its own lifecycle

Every repo cuts its own release branch, bumps its own version, tags independently, and back-merges
on its own. There is no shared release branch and no monorepo pointer commit unless the project
already has one.

**Do not force version alignment across repos.** Matching version numbers on independently-versioned
services is cosmetic: it implies a compatibility guarantee the numbers do not enforce, and it forces
empty MAJOR/MINOR bumps on repos with nothing to ship. What actually needs recording is which
versions were *validated together* — that belongs in the release notes.

## Deploy order comes from contract direction

Identify what couples the repos before choosing an order:

- shared event/message schemas between services
- API or protocol surfaces one repo calls on another
- shared contract or schema packages
- frontend depending on new backend endpoints

**Rule: whichever side must tolerate both old and new goes first.** In practice this means the
producer of a backward-compatible change deploys ahead of its consumer — the new backend accepts both
shapes before any client emits the new one, so no window exists where a client speaks a language the
server hasn't learned.

A change that is *not* backward compatible has no safe order. That is the signal to split it into two
releases: first make the receiver accept both forms, ship it, then switch the sender.

## Verification and rollback

**Before tagging any repo in the set**, run the C5 content gate on every one of them. A single repo
carrying stale content can revert a hotfix while its siblings deploy cleanly, which presents as a
partial, confusing outage.

**Deploy sequentially with verification between steps**, not all at once. The order only protects you
if each step is confirmed before the next begins.

**Rollback is not symmetric.** Rolling back the first-deployed repo while later ones are live
reintroduces the incompatibility the ordering avoided. Roll back in reverse deploy order, or roll
forward. Decide which before starting — mid-incident is the wrong time to work it out.

## Release notes

Record what a version-number match cannot: which versions were validated together, the deploy order
used, and any feature flags or kill switches involved.

```markdown
## Release YYYY-MM-DD

Deploy order: service-a v1.4.0 → service-b v2.7.1 → frontend v0.9.3

### Coupling
- <contract/schema that spans repos, and which direction it flows>

### Verification focus
- <what to watch after each step, and the signal that says "safe to proceed">
```

Group by user-facing capability rather than by repo or commit — the audience cares what changed, not
which repository it landed in.
