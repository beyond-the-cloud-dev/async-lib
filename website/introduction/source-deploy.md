---
outline: deep
---

# Deploying the Source

## TL;DR

The code lands in your org with no namespace, so there is no prefix, nothing to copy from `extras`
and nothing to declare `global`. What you own instead is the upgrade path, because nothing tracks
the version for you.

If you installed the [unlocked package](/introduction/packaged-install), this page is not for you.

## What you get

| | |
| --- | --- |
| Classes | `Async`, `QueueableJob`, `ChunkJob`, `AsyncMock`, the builders, and their tests |
| Object | `AsyncResult__c` with every field and its page layout |
| Custom Metadata | `QueueableJobSetting__mdt`, its layout, and one record named `All` |
| Permission set | `AsyncResultAccess` |

All of it `public`, in your default namespace: `Async.queueable(...)`, `extends QueueableJob`,
`AsyncResult__c`.

## Three ways to deploy

### Deploy button

<a href="https://githubsfdeploy.herokuapp.com?owner=beyond-the-cloud-dev&repo=async-lib&ref=v2.8.0">
  <img alt="Deploy to Salesforce" src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

The button deploys the latest release, `v2.8.0`, and the link is updated with every release the
same way the package link is. To deploy an older release put its tag in the URL, and for whatever
was merged last use `ref=main`:

```
https://githubsfdeploy.herokuapp.com?owner=beyond-the-cloud-dev&repo=async-lib&ref=main
```

Tags are on the [releases page](https://github.com/beyond-the-cloud-dev/async-lib/releases).

### Salesforce CLI

```bash
git clone https://github.com/beyond-the-cloud-dev/async-lib.git
cd async-lib
git checkout v2.8.0
sf project deploy start --source-dir force-app --target-org your-org
```

Production, and any org that requires tests, needs `--test-level RunLocalTests`. That runs
`AsyncTest`, about 300 tests, **and every test already in your org**. If an unrelated test of yours
is failing, the deploy fails with it. For a sandbox you can use
`--test-level RunSpecifiedTests --tests AsyncTest`; production still needs `RunLocalTests`.

### Vendor the source

Copy `force-app/main/default/` into your own repository and deploy it with the rest of your code.
From then on you own upgrades: diff the next tag against what you copied. The PMD suppressions in
the classes travel with them, so a vendored copy passes the same static analysis it passes here.

## Upgrading

Redeploy from the new tag, the same way you deployed the first time. Read the
[release notes](https://github.com/beyond-the-cloud-dev/async-lib/releases) first: a major version
means a breaking change, and the notes say what to change.

::: warning A redeploy replaces the `All` record

`force-app/main/default/customMetadata/` holds one `QueueableJobSetting__mdt` record, `All`, with
only `IsDisabled__c` and `QueueableJobName__c` set. A metadata deploy **replaces** a Custom
Metadata record rather than merging it. Anything you set on `All` in the org that is not in that
file, `CreateResult__c`, `MaxRetries__c`, `LoggerClass__c`, `StoreJobPayload__c`, is cleared.

Leave that folder out when you upgrade:

```bash
sf project deploy start --source-dir force-app/main/default/classes \
    --source-dir force-app/main/default/objects \
    --source-dir force-app/main/default/layouts \
    --source-dir force-app/main/default/permissionsets \
    --target-org your-org
```

Or note your `All` values first and put them back after. The per-job records you created yourself
are not in the repository and are untouched either way.

:::

## After the deploy

1. Assign `AsyncResultAccess` to whoever should read `AsyncResult__c` in the UI or in reports. The
   framework writes those records in system context and does not need it.
2. Open `QueueableJobSetting__mdt` and decide what `All` should say. Nothing is on by default: no
   result rows, no retry, no logger, no payload storage. See
   [Configuration Safety](/explanations/configuration-safety) for what a wrong value does.
3. Write your first job. [Getting Started](/getting-started).

## Switching to the package later

The code changes are mechanical, and [Installing as a Package](/introduction/packaged-install) is
the checklist. In short:

- every class reference gains `btcdev.`, every object and field gains `btcdev__`
- any class registered in `LoggerClass__c` or `JobSerializerClass__c` becomes `global`. Keep them
  `public` until then, like any other class of yours; a source deploy has no boundary for `global`
  to cross
- the features that copy or store a job start needing the
  [`extras`](https://github.com/beyond-the-cloud-dev/async-lib/tree/main/extras) base classes

The data does not move. `AsyncResult__c` and `btcdev__AsyncResult__c` are different objects, so
history stays on the old one and new jobs write to the new one. Uninstall the source classes only
once nothing references them.
