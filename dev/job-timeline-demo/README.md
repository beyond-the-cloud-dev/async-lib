# Job Timeline demo

Real jobs for the Async Jobs card, to test it by hand and to retake the docs screenshots. Scratch orgs only: `seed` changes `QueueableJobSetting.All`, and `cleanup` deletes every `AsyncResult__c` row.

Not part of the package. Needs `sf`, `jq`, and for screenshots a global `playwright` (`npm i -g playwright`).

```bash
bash dev/job-timeline-demo/run.sh <action> [org-alias] [chromium-path]
```

Org alias defaults to `async-lib-scratch`.

| Action | What it does | Look at |
| --- | --- | --- |
| `seed` | deploys the demo jobs and settings, runs failed, retried, chunk, priority and 80 small chains. Settles in about 4 minutes | `Northwind Order #10248`, and `Fabrikam Order #20001` for more than 50 chains |
| `live` | a long chain with a runtime insert, a retry and a failure | `Northwind Order #10248` |
| `live-priority` | a job that adds a priority job and a plain job after 30 s, then a chunk run. Watch them arrive with `NEW`, in run order | `Northwind Order #10248` |
| `live-delay` | a chain with three delays and one failure, about 5 minutes. Shows `DELAYED`, `RUNNING`, `RUNNING \| DELAYED`, then `RUNNING \| ✕ 1 \| DELAYED`, and ends `FAILED` | `Northwind Order #10248` |
| `live-quick` | two plain jobs, about 90 seconds, to watch a chain go in and out of `In flight` | `Northwind Order #10248` |
| `showcase` | the runs in the docs screenshots, a minute apart. About 7 minutes | `Acme Order #00124` |
| `screenshots` | retakes all six images in `website/public/images/job-timeline`. Run `showcase` first | |
| `cleanup` | deletes every result row and the demo accounts | |
| `reset` | puts `QueueableJobSetting.All` back to the repo defaults. Do this before `verify.sh full` | |

An idle card does not poll, so refresh it after starting a `live` action. It polls by itself from then on.

Priority examples from `seed` are on `Northwind Order #10248`: `Priority set before start` shows the priority job first, in run order. Open the same card after `live-priority` has finished and the added jobs sit in place with no `NEW`.

Changed the card? Add an example here if a new state has none, then run `showcase` and `screenshots`.
