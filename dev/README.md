# dev

For people working on Async Lib. You don't need any of this to use it.

| Folder | What it is |
| --- | --- |
| `verify` | `bash dev/verify/verify.sh <phase>`, from `static` up to `all`. Run it before a PR |
| `package-tests` | tests that use the library the way a subscriber does, through the namespace |
| `job-timeline-demo` | real jobs to test the Async Jobs card by hand and to retake the docs screenshots |
| `docs` | code style and the rules for changing a shipped `global` surface |
| `pmd` | the PMD ruleset |
| `jest-mocks` | mocks for LWC Jest tests |

`verify` creates scratch orgs when they are missing. It uses the `target-dev-hub` from `sf config`, or `ASYNC_LIB_DEVHUB` if you set it.
