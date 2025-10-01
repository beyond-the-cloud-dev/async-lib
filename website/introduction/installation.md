---
outline: deep
---

# Installation <Badge type="tip" text="v2.0.0" />

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