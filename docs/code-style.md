# Code Style

## Comments

**Code must be self-explaining. A comment is a last resort, not a default.**

Classes, methods, fields and variables carry the meaning. If a comment feels
necessary, that is almost always a naming or structure problem, so fix the code
instead:

| Instead of a comment saying                  | Do this                                                      |
| -------------------------------------------- | ------------------------------------------------------------ |
| what a block does                            | extract it into a method whose name says it                  |
| why a `catch` swallows                       | name the handler method, `reportWithoutAffectingTheJob(...)` |
| that a static resets each transaction        | name the field, `loggerCacheForThisTransaction`              |
| that a class must be `global` to be resolved | name the method, `newInstanceOfGlobalClass(...)`             |
| what a flag means                            | name the variable, `retryWillRestore`                        |

Delete on sight: comments restating the code, section banners, commented-out
code, narration ("first we...", "now handle..."), and ApexDoc that only echoes
the signature.

### The bar for keeping one

A comment earns its place only when a competent Apex developer would be
**surprised or misled** without it, and no name or structure can carry it. In
practice that means a platform quirk or a deliberate choice that looks wrong:

```apex
// A failed cast is the only way to read the runtime type with its namespace.
String.valueOf((DateTime) job);
```

```apex
// List.sort() does not define the order of equal elements, so equal priority needs an
// explicit tiebreak to keep jobs running in the order they were chained.
```

Rules of thumb that stay in prose belong in `website/explanations/`, not in the
source. If the reason is about **how consumers use the library**, document it
there and link it from the error message. If it is about **how the framework may
evolve**, it belongs in `docs/api-evolution.md`.

### The two allowed exceptions

**PMD suppression justification.** Every `@SuppressWarnings` carries a header
block saying why the rule is a false positive here. Without it a suppression is
indistinguishable from hiding a defect.

```apex
/**
 * PMD False Positives:
 * - ExcessivePublicCount: one fluent method per job option
 **/
@SuppressWarnings('PMD.ExcessivePublicCount')
```

**A member that must never be deleted.** Where the reason for keeping
dead-looking code is invisible, say so, because the next maintainer will
otherwise remove it.

```apex
/**
 * Superseded by Async.Retryable.resetBeforeRetry(Integer). Nothing calls this any more.
 * It cannot be deleted: dropping a global member makes the package install fail in every
 * subscriber org that referenced it. See docs/api-evolution.md.
 **/
```

## Why ApexDoc is not enforced

`pmd/ruleset.xml` deliberately excludes `category/apex/documentation.xml`.
Requiring `@description` and `@param` on every member produces exactly the
restatement this policy exists to remove. Editor plugins ship that rule on by
default, so expect warnings; ignore them.

## Design

Ordinary clean-code expectations apply, and they matter more here than in an org
codebase because this is a library whose public surface is
[frozen once shipped](/docs/api-evolution.md):

- **KISS.** The smallest thing that solves the actual problem. No configuration
  nobody asked for.
- **DRY, within reason.** Duplication in tests is often clearer than a shared
  helper. Duplication in framework logic is a bug waiting to diverge.
- **SOLID.** Most relevant here is interface segregation: many small capability
  interfaces beat one fat one, because Apex has no default methods, so a fat
  interface can never gain a member.
- **Composition over inheritance.** A consumer has one inheritance slot. Do not
  spend it. Prefer a marker interface the consumer can add to any class.
- **Guard clauses over nesting.** Early return, and let the shape of the method
  show the flow.
