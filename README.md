<div align="center">
  <a href="https://async.beyondthecloud.dev">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="./website/public/logo.png">
      <img alt="Async Lib logo" src="./website/public/logo.png" height="98">
    </picture>
  </a>
  <h1>Async Lib</h1>

<a href="https://beyondthecloud.dev"><img alt="Beyond The Cloud logo" src="https://img.shields.io/badge/MADE_BY_BEYOND_THE_CLOUD-555?style=for-the-badge"></a>
<a ><img alt="API version" src="https://img.shields.io/badge/api-v64.0-blue?style=for-the-badge"></a>
<a href="https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-mit-green?style=for-the-badge"></a>

[![CI](https://github.com/beyond-the-cloud-dev/async-lib/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/beyond-the-cloud-dev/async-lib/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/beyond-the-cloud-dev/async-lib/branch/main/graph/badge.svg)](https://codecov.io/gh/beyond-the-cloud-dev/async-lib)
</div>

---

The Async Lib provides easy way for managing asynchronous processes in Salesforce.

Async Lib is part of [Apex Fluently](https://apexfluently.beyondthecloud.dev/), a suite of production-ready Salesforce libraries by Beyond the Cloud.

For more details and examples, please look into this [post](https://blog.beyondthecloud.dev/blog/apex-queueable-processing-framework).

## Documentation

Visit https://async.beyondthecloud.dev/ to view the full documentation.

## Features

- **Queueable Chain**: Eliminate the issues with "Too many queueable jobs" by using the `Async.queueable()` method to enqueue jobs in both synchronous and asynchronous context.
  - Framework will automatically handle the chaining of jobs, allowing you to enqueue multiple jobs without hitting the limit, in the same time using as many jobs as possible.
  - Each job will get its own Custom Job ID, which can be used to track the job status.
  - Async Result Custom Object will be created for each job, allowing you to track the status of each job.
  - Support for finalizers, which are executed after the job is processed, allowing you to handle any finalization logic.
  - Allows for manually adding jobs to chain
- **Schedulable Jobs**: Schedule jobs to run at specific times using the `Async.schedulable()` method.
  - Convert any `QueueableJob` or `Database.Batchable` into a schedulable job, by using the `asSchedulable()` method.
  - Support easier cron expressions using the `CronBuilder` class.
- **Batchable Jobs**: Execute batch jobs using the `Async.batchable()` method.
- **Custom Metadata Configuration**: Configure the QueueableJob settings using the `QueueableJobSettings__mdt` custom metadata type to enable or disable jobs, and to control the creation of Async Result records.
- **Custom Object for Async Results**: The `AsyncResult__c` custom object is created for each processed queueable job, allowing you to track the chained job status and details.

## Deploy to Salesforce

<a href="https://githubsfdeploy.herokuapp.com?owner=beyond-the-cloud-dev&repo=async-lib&ref=main">
  <img alt="Deploy to Salesforce"
       src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

## Contributors

<a href="https://github.com/beyond-the-cloud-dev/async-lib/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=beyond-the-cloud-dev/async-lib" />
</a>

# License notes:
- For proper license management each repository should contain LICENSE file similar to this one.
- each original class should contain copyright mark: © Copyright 2025, Beyond The Cloud Dev Authors
