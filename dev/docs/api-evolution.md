# API Evolution Rules

Async Lib ships as a namespaced unlocked package. Anything a subscriber compiles
against is frozen the moment it ships. These rules exist because breaking them
does not fail our build, it fails the subscriber's **package install**, which is
the worst failure mode available to us: our Apex never runs, so our error
messages never reach them, and they cannot upgrade at all until they edit their
own code.

## The rule

**When you need an implementation from the consumer, use an interface. Never an
abstract member on a shipped class.**

Interfaces can be retired. Abstract members cannot.

- Adding a new interface breaks nobody, because nobody implements it yet.
- Retiring an interface is just "stop checking for it". Subscribers who still
  implement it keep compiling, since implementing an unused interface is
  harmless.
- Adding an abstract member to a shipped global class breaks every existing
  subclass at compile time, so the install fails.
- Removing a global member breaks every subscriber that referenced it, so the
  install fails.

Corollary: enforcement has to live in a **runtime gate**, not in the type
system. The type system cannot be changed after v1, so it cannot be where the
rules live.

## Evidence

All of this was measured on a real unlocked package version installed into a
`--no-namespace` scratch org, not inferred from documentation.

### Removing a global member

`global virtual void resetForRetry()` downgraded to `public`, built, and
installed over an org running the previous version with a subscriber class that
overrode it.

The **build succeeded**. Unlocked packages do not enforce the managed-package
rule at version create time, so nothing stops you shipping this.

The **install failed** and rolled back:

```
Apex compile failure, Details: Apex class SubscriberOverridesReset: line 8, column 26:
@Override specified for non-overriding method: void SubscriberOverridesReset.resetForRetry()
```

### Adding an abstract member

Same mechanism in reverse. A subscriber's existing
`MyChunk extends btcdev.ChunkJob` stops compiling the moment `ChunkJob` gains an
abstract method, so the install fails the same way.

### What interfaces can do

A nested interface in a namespaced package works completely across the boundary:

| Behaviour                                                   | Result                                     |
| ----------------------------------------------------------- | ------------------------------------------ |
| Subscriber writes `implements btcdev.Async.Retryable`       | compiles                                   |
| Package code runs `job instanceof Retryable`                | `true` for implementers, `false` otherwise |
| Package code invokes the subscriber's body with an argument | runs, argument arrives intact              |

### Interface methods must not collide with an inherited virtual

An interface method whose signature **matches** a method the consumer already
inherits is satisfied silently. The consumer writes nothing and it compiles:

```apex
public class DeclaresOnly extends Base implements SameSignature {
} // compiles, no body
```

Give the interface method a signature that cannot be satisfied by an inherited
member, and the compiler enforces it:

```
Class SubIfaceNoBody must implement the method: void btcdev.Async.Retryable.resetForRetry(Integer)
```

## Safe and unsafe changes

| Change                                                |         Safe?         |
| ----------------------------------------------------- | :-------------------: |
| Add a new interface                                   |          yes          |
| Add a `virtual` method with a body to a shipped class |          yes          |
| Add a field to a shipped class                        |          yes          |
| Add an overload                                       |          yes          |
| Stop calling a method we used to call                 |  yes, behaviour only  |
| Add an **abstract** member to a shipped class         | **no, install fails** |
| Remove a global member                                | **no, install fails** |
| Narrow a global member to `public`                    | **no, install fails** |
| Change a global signature                             | **no, install fails** |

`scripts/api-surface.sh` rewrites `public ` to `global ` for the files it lists,
so every `public` member in those files is part of the frozen surface.
`protected` and `private` members are not rewritten and stay free to change.

## When you cannot avoid a breaking change

Prefer a runtime throw at enqueue over anything that blocks the install. It
lands in the caller's transaction, so it surfaces in the consumer's own test run
on a sandbox rather than in production, the upgrade still installs, and the
exception can carry the migration instructions. An install failure can carry
nothing.
