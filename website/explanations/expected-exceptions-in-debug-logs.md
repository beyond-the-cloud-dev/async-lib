---
outline: deep
---

# Expected Exceptions in Debug Logs

## TL;DR

If your debug logs show an entry like this while using Async Lib:

```
System.TypeException: Invalid conversion from runtime type MyJob to Datetime
```

it is **expected and harmless**. The framework throws and catches this
exception on purpose to detect your job's class name. It never reaches your
code and does not affect job processing. No action is needed.

## Why Does It Happen?

Apex has no reflection API that returns the class name of an object instance.
The framework needs the full class name (including the namespace and the outer
class for inner classes) to:

- build the job's unique name,
- match `QueueableJobSetting__mdt` records to jobs,
- resolve the job type again during [deep clone](/explanations/job-cloning).

The only reliable way to get the name is a well-known Apex workaround: cast the
instance to an incompatible type, catch the `TypeException`, and read the class
name out of the exception message. This is what
`QueueableJob.getFullClassName()` does:

```apex
private String getFullClassName(Object job) {
    String result;
    try {
        DateTime typeCheck = (DateTime) job;
    } catch (System.TypeException expectedTypeException) {
        String message = expectedTypeException.getMessage()
            .substringAfter('Invalid conversion from runtime type ');
        result = message.substringBefore(' to Datetime');
    }
    return result;
}
```

The cast always fails, the catch block always runs, and the class name comes
out of the message. Alternatives like `String.valueOf(instance)` are not
reliable: they break when a class overrides `toString()` and do not always
include the namespace or the outer class name.

## Why Does a Caught Exception Show Up in the Log?

Salesforce writes an `EXCEPTION_THROWN` entry to the debug log for every
thrown exception, even when it is caught immediately. The log line does not
mean the exception escaped.

If a job had actually failed, you would see it as a `FATAL_ERROR` log entry
and in the job's `AsyncResult__c` record (`Status__c`, `ExceptionType__c`,
`ExceptionMessage__c`).

## When Will I See It?

Whenever the framework reads a job's class name: at enqueue time, when
resolving `QueueableJobSetting__mdt` settings, and when recording results.
Several entries per transaction are normal, especially for chains with
multiple jobs and finalizers.
