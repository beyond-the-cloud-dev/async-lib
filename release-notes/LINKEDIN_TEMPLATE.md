# LinkedIn post template — Async Lib release

This file is the source of truth for the LinkedIn post format. The
`/linkedin-post` slash command renders it for a specific release. Fields wrapped
in `{{…}}` are substituted at render time.

Keep the tone enthusiastic but specific. Lead with the headline change. List 3–5
highlights using emoji bullets (✅ / 🚀 / ✨ / 🐛 / 📦 / 🔧). End with the
standard Beyond The Cloud cross-link block.

---

## Template

```text
New Async Lib release v{{version}} is here! 🚀

{{headline}}

What's included?

{{#each highlights}}
{{emoji}} {{text}}
{{/each}}

{{#if linked_libs}}
Also worth checking:
{{#each linked_libs}}
{{name}} v{{version}}: {{url}}
{{/each}}
{{/if}}

Release notes:
Async Lib v{{version}}: {{release_url}}

---
Apex Fluently: https://apexfluently.beyondthecloud.dev/
Async Lib: https://async.beyondthecloud.dev/
SOQL Lib: https://soql.beyondthecloud.dev/
DML Lib: https://dml.beyondthecloud.dev/
```

## Example — reference post (SOQL Lib v6.10.0 + DML Lib v3.1.0 multi-release)

```text
New SOQL Lib release v6.10.0 is here! 🚀
New DML Lib release v3.1.0 is here! 🚀

What's included? A few small improvements and edge-case fixes.

A new library from Beyond The Cloud: Test Lib 😎
https://lnkd.in/d7KjdkAC

It is currently in beta, as we are making sure the interface is easy to use and free of bugs. Test Lib helps with creating test data, but it also includes a Mocker that allows you to create records with populated formula fields, child records, relationships, and roll-up summaries. It works especially well together with SOQL Lib.

In addition, we have Templates to define different variations, and Randomizers to assign random values to specific fields. Everything is wrapped in a TestModule, which can include not only a Builder and a Mocker, but also utility methods for a specific object.

We are open to any suggestions on how to make it even better.

Release notes:
SOQL Lib v6.10.0: https://lnkd.in/dF3necpa
DML Lib v3.1.0: https://lnkd.in/dYuWAdq4

---
Apex Fluently: https://lnkd.in/dqSTKut3
SOQL Lib: https://lnkd.in/dAFbrYsX
DML Lib: https://lnkd.in/dhFCqiJY
Async Lib: https://lnkd.in/dkcyxGYr
```

## Single-feature release (smaller change)

```text
New Async Lib release v{{version}} is here! 🚀

{{one-sentence what changed and why it matters}}

✅ {{highlight 1}}
✨ {{highlight 2}}
🐛 {{highlight 3 — only if there were fixes}}

Release notes: {{release_url}}

---
Apex Fluently: https://lnkd.in/dqSTKut3
SOQL Lib: https://lnkd.in/dAFbrYsX
DML Lib: https://lnkd.in/dhFCqiJY
Async Lib: https://lnkd.in/dkcyxGYr
```

## Rendering rules (for `/linkedin-post`)

- `{{version}}` — from `sfdx-project.json`
  `.packageDirectories[0].versionNumber` (strip `.NEXT`), or from the latest
  `v*` tag.
- `{{release_url}}` —
  `https://github.com/beyond-the-cloud-dev/async-lib/releases/tag/v{{version}}`.
- `{{headline}}` — extract the lead bullet from `## New Features` in
  `release-notes/v{{version}}.md`. Fall back to "A few small
  improvements and edge-case fixes." for patch releases with no new features.
- Highlights — at most 5, pulled in this priority order: New Features →
  Improvements → Bug Fixes. Compress wording; LinkedIn favors short bullets.
- Emoji order: 🚀 for new feature, ✨ for improvement, 🐛 for bug fix, 📦 for
  packaging, 🔧 for internal/tooling. Keep order consistent.
- Never invent a feature or fix that isn't in the release notes file.
- Always include the four-link Beyond The Cloud block at the end, in the order
  shown above.
