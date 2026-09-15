---
outline: deep
---

# Installation <Badge type="tip" text="v3.0.0" />

Two ways to get Async Lib into an org. Pick one, then follow its guide.

| | Unlocked package | Source deploy |
| --- | --- | --- |
| How | one install link | deploy button, `sf` CLI, or copy the source |
| Namespace | `btcdev.` on every class, `btcdev__` on every field | none |
| Upgrade | install the next version | redeploy from the next tag |
| Extra setup | a few `extras` classes for features that copy or store a job | none |
| Pick it when | you want a versioned, uninstallable unit and an upgrade path you do not maintain | you want to read, vendor or patch the code, or you cannot install packages |

## Install as Unlocked Package

Install the latest version of Async Lib as an unlocked package:

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04tP6000003i1ujIAA">
  <img alt="Install Unlocked Package" src="https://img.shields.io/badge/Install-Unlocked%20Package-blue?style=for-the-badge&logo=salesforce">
</a>

```
https://login.salesforce.com/packaging/installPackage.apexp?p0=04tP6000003i1ujIAA
```

Then follow [Installing as a Package](/introduction/packaged-install): the prefix, the `extras`
classes, what has to be `global`, and the permission set.

## Deploy the Source

<a href="https://githubsfdeploy.herokuapp.com?owner=beyond-the-cloud-dev&repo=async-lib&ref=v3.0.0">
  <img alt="Deploy to Salesforce" src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

Or with the Salesforce CLI:

```bash
git clone https://github.com/beyond-the-cloud-dev/async-lib.git
cd async-lib
sf project deploy start --source-dir force-app --target-org your-org
```

Then follow [Deploying the Source](/introduction/source-deploy): deploying a tag rather than
`main`, production test levels, vendoring, and what a redeploy does to your `All` record.
