---
outline: deep
---

# Installation <Badge type="tip" text="v2.0.0" />

## Install as Unlocked Package

Install the latest version of Async Lib as an unlocked package:

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04tP6000002cgEnIAI">
  <img alt="Install Unlocked Package" src="https://img.shields.io/badge/Install-Unlocked%20Package-blue?style=for-the-badge&logo=salesforce">
</a>

```
https://login.salesforce.com/packaging/installPackage.apexp?p0=04tP6000002cgEnIAI
```

::: tip
When installed as a package, all classes use the `btcdev` namespace prefix (e.g., `btcdev.QueueableJob`, `btcdev.Async`). If you use [`.deepClone()`](/api/queueable#deepclone), see [Deep Clone in Packages](/explanations/deep-clone-in-packages) for a required override.
:::

## Deploy via Button

Deploy to your Salesforce org using the deploy button:

<a href="https://githubsfdeploy.herokuapp.com?owner=beyond-the-cloud-dev&repo=async-lib&ref=main">
  <img alt="Deploy to Salesforce" src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

## Copy and Deploy

Or clone the repository and deploy using SFDX:

```bash
git clone https://github.com/beyond-the-cloud-dev/async-lib.git
cd async-lib
sf project deploy start -p force-app -u your-org-alias
```