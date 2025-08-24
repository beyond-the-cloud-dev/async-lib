---
outline: deep
---

# Installation <Badge type="tip" text="v1.0.0" />

## Install via Package

Install the SOQL Lib unmanaged package to your Salesforce environment:


`/packaging/installPackage.apexp?p0=04tP6000001w95Z`

<a href="https://test.salesforce.com/packaging/installPackage.apexp?p0=04tP6000001w95Z" target="_blank">
    <p>Install on Sandbox</p>
</a>

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04tP6000001w95Z" target="_blank">
    <p>Install on Production</p>
</a>

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