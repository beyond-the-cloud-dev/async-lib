# Async Lib

---

The Async Lib provides easy way for managing asynchronous processes in Salesforce.

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

# TODO

1. Add option to add Finalizers to chain
2. Flag to disable all the queueable jobs
3. Use Finalizers to handler limit errors, to proceed with next job (consider if there should be custom finalizer created by normal queueable in chain, not a real Finalizer)
4. Add smart job execution:
   1. if finalizer added - run in separate queueable job
   2. If not added - run in Chainable Finalizer, and execute next job from there
5. Improve getting jobId for scheduled jobs
6. Add option to retry job
7. Allow for chain manipulation (adding/removing jobs, changing order)
8. Allow for setting job priority
9. Allow for setting job dependency
10. Add support for custom job types (e.g., Batchable, Schedulable)