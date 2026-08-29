# Package tests

Tests that exercise Async Lib the way a **subscriber** does, through a namespace
prefix, rather than as local source.

They exist because the normal Apex test suite cannot see two whole classes of bug:

- `scripts/create-unlocked-package-version.sh` rewrites `public` to `global`
  before building a package. A class missing from that list compiles fine in every
  local test and is unusable once installed.
- Source in the same org is namespace-internal, so `public` is enough. In a
  subscriber org it is not.

## Layout

| Path            | What it is                                                                         |
| --------------- | ---------------------------------------------------------------------------------- |
| `run.sh`        | Runs everything below against the current default org.                             |
| `anonymous/`    | Anonymous Apex scripts. Cheap API-surface smoke tests: does this compile and enqueue from a consumer namespace. |
| `consumer-app/` | A small SFDX project of consumer classes, deployed into the target org. The `@IsTest` ones assert real behaviour. |

`run.sh` deploys `consumer-app`, runs every `anonymous/*.apex` script, then runs
every `@IsTest` class it finds in `consumer-app`. New test classes are picked up
automatically, no registration needed.

## The two kinds of test, and why both

**`anonymous/*.apex`** assert synchronously, on the value `enqueue()` returns.
They prove the API is reachable and callable across a namespace. They do **not**
prove the job did anything: the assertions run before the job does.

**`consumer-app` `@IsTest` classes** wrap work in `Test.startTest()` /
`Test.stopTest()`, which forces queued jobs to run before the assertions. That
makes async deterministic, so these can assert real outcomes: that a chunk run
processed every record, that `onFinalFailure` fired exactly once, that a retry did
not duplicate a chained job.

Prefer adding to `consumer-app` for anything behavioural. An anonymous script that
"passes" while the behaviour is broken is a real failure mode we have hit.

## Running

Against a namespaced scratch with source deployed (fast, no package build):

```bash
sf config set target-org async-lib-btcdev-scratch
./package-tests/run.sh
```

Against a real installed package, which is the only check that covers the
`public` to `global` rewrite:

```bash
./scripts/verify-package-install.sh 04t...
```

`scripts/release.sh` runs that second one automatically after it builds a version,
before anything irreversible happens, so a bad build is never promoted.
