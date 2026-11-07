# Contributing

For the full contributing guide, please visit our documentation site:

**[Contributing Guide](https://yeongseon.github.io/azure-container-apps-practical-guide/contributing/)**

## Quick Start

1. Clone the repository
2. `pip install -r requirements-docs.txt` to install all documentation dependencies (Material theme, macros plugin, and the capture toolkit required by `mkdocs.yml`)
3. `mkdocs serve` to preview locally
4. `mkdocs build --strict` to validate
5. Submit a Pull Request

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community guidelines.

## Title Convention

This section is the single source of truth for issue, pull request, and commit titles in this repository. `AGENTS.md`, the pull request template, and the documentation site point here instead of restating the rules; the issue forms only prefill a matching prefix.

Issues, pull requests, and the final squash commit on the default branch all use:

```text
type: description
type(scope): description
```

- Write titles in English.
- `type` and `scope` are lowercase. Put exactly one space after the colon.
- `scope` is optional. Add it only when it narrows the area; do not add one just for uniformity.
- `description` states what changes and why, concisely. Start with a lowercase word, but keep the spelling of API names, acronyms, error codes, and proper nouns.
- No trailing period.
- No priority, size, status, or owner markers, and no bracket prefixes such as `[Bug]`, `[Feature]`, or `[WIP]`. Use labels and Draft pull requests instead.
- An issue title may describe the problem; the pull request title describes the change that resolves it. Keep them aligned when they cover the same work, without forcing identical wording when the scope differs.
- Do not put issue numbers in pull request titles. Link issues in the pull request body with `Closes #123` or `Refs #123`.

| type | use for |
|---|---|
| `feat` | a user-facing feature or capability |
| `fix` | a bug fix in product behavior |
| `docs` | documentation only |
| `test` | adding or changing tests |
| `perf` | a performance improvement |
| `refactor` | internal restructuring that keeps external behavior |
| `ci` | CI and automation workflows |
| `build` | build, packaging, and dependency changes |
| `chore` | maintenance that fits none of the above |
| `style` | formatting only, no behavior change |
| `revert` | reverting an earlier change |

A breaking change adds `!` before the colon: `type!: description` or `type(scope)!: description`. Whether a change is breaking is decided by the maintainers, not by the title alone. This repository does not publish versioned releases, so titles do not drive versioning.

Examples:

```text
fix: decode nonempty NULL-only collection results
feat(cli): add a JSON output option
docs(readme): clarify the local setup steps
refactor!: rename the public configuration keys
```

Not accepted: `[Bug] crash on save` (bracket prefix, no type), `Fix: crash on save` (uppercase type), `feature: add export` (type not in the table), `fix: crash on save.` (trailing period), `fix: crash on save (#123)` (issue number in the title).

Pull requests are squash-merged and the pull request title becomes the final commit title. GitHub appends the pull request number, for example `fix: decode nonempty NULL-only collection results (#503)`. The **PR title** check validates the format whenever a pull request is opened, edited, reopened, or updated. Individual commits on a branch are not checked.

The check enforces the syntax and nothing else. A title is `type`, an optional `(scope)`, an optional `!`, a colon followed by exactly one ASCII space, and a description, where:

- `type` is one of the eleven lowercase types in the table;
- `scope`, when present, starts with a lowercase ASCII letter or digit and continues with lowercase ASCII letters, digits, or `.`, `_`, `/`, `,`, `-`;
- the title is valid UTF-8 on a single line, without control characters (a tab included) or Unicode line and paragraph separators;
- the description is non-empty and has no leading or trailing whitespace (any Unicode space, such as a no-break space, counts) or invisible format character (such as a zero-width space or a byte order mark);
- the description does not end with an ASCII period, does not start with `[` (a bracket marker such as `[WIP]`), and contains no `#123`-style issue number, meaning a `#` followed by ASCII digits that is not directly preceded by an ASCII letter or digit. `C#7` and `a#123` are accepted; `(#123)`, `#123`, and `é#123` are rejected.

The remaining wording guidance (English, a lowercase first word, no priority, size, status, or owner markers) is a review expectation that the check does not verify.

Issue titles are a review expectation. Maintainers can clarify titles during triage; the new-issue quality check warns about missing structure rather than blocking issue creation.

## Writing Actionable Issues

Before opening a bug, documentation, feature, or decision/tracker issue, search for an existing parent or duplicate. Use the appropriate form under `.github/ISSUE_TEMPLATE/` and provide: problem/impact, evidence with source and as-of date, affected scope and exclusions, measurable acceptance criteria, and a verification/closure plan. A manual decision can use a decision record or confirmed external action in place of code tests. Do not invent verification dates, Azure executions, screenshots, approvals or numeric baselines; mark unknowns explicitly. Link child work to its parent and prefer small reviewable increments.

The same rules apply to API-created and agent-authored issues. See `AGENTS.md` (Issue Quality Contract) for type-specific evidence integrity and PII requirements. The new-issue quality workflow detects missing structural information, but human review remains necessary for technical correctness. Existing open issues are audited selectively under #419 rather than bulk rewritten.
