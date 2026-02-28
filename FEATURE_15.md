IDEA:

Yeah, so this is something I have planned for Async Lib enhancements here. So
something like that will be available in the lib, but not sure exactly when. I
wanted to work on it last weekend, but in the end had too many other obligations
to touch it. But the high-high-level overview is there if you want to look. We
can think together about it, since I also don’t have all the answers here.

For sure, there should be:

Option to enable or disable this feature via a flag Option in code to mark given
queueable job that it NEEDS to run in Queueable context and needs to run ALONE
Logic that determines if the job: should be even spawned (if in Sync context)
should run in a separate Queueable job (if in queueable already)

The above logic should take into account the following: Governor limits - that
means that ideally we should know the approximate of the limits the job would
use for that we can have 2 approaches - more sophisticated - getting the results
after the job and store it, so we can have the scheduled job that will update
job metrics with the number of resources it uses or easier approach, to just set
some hard thresholds for it

Any other actions that we know needs to be separate (e.g. mixed dml exceptions
and some jobs need to run alone).

It would require some additional logging AND retry operations in case some logic
was merged by Orchestrator, and failed due to it. (edited)
