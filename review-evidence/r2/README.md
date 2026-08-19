# Sanitized public R2 review evidence

This tree publishes the review evidence for Higress PRs
[#4286](https://github.com/higress-group/higress/pull/4286),
[#4287](https://github.com/higress-group/higress/pull/4287), and
[#4288](https://github.com/higress-group/higress/pull/4288). Each PR directory
contains the executable or source-level harness, machine-readable results, key
logs, and a `SHA256SUMS` manifest for the files that are actually public here.

## Sanitization and provenance

- Local paths below the original user workspace were replaced with
  `<workspace>` in recorded logs.
- The synthetic token used only by the PR #4288 mock was replaced with
  `<redacted-test-token>` wherever the Envoy debug log echoed configuration.
- Public harness scripts use explicit environment variables instead of the
  original machine's absolute checkout paths.
- Large compiled artifacts and the complete kind cluster export were not
  published. Their recorded SHA-256 values remain in the reports and original
  full-bundle manifests.
- Benchmark samples, HTTP response bodies, counters, revisions, image digests,
  and test outcomes were not altered.

`SHA256SUMS.full` is the untouched manifest from each original retained bundle.
It intentionally names files that were omitted or sanitized, so it is included
for provenance and is not expected to validate this curated tree. Its own hash
is preserved below.

| PR | Public directory | Original full-manifest SHA-256 |
|---|---|---|
| #4286 | [`pr-4286/`](pr-4286/) | `0945fb98d8070381325bee6a615ea18492aa31d87ae286e8858f11a38d793160` |
| #4287 | [`pr-4287/`](pr-4287/) | `76f6d342d2cec9564b8d63e11a108f224695ab03002b144d5f5169390add8759` |
| #4288 | [`pr-4288/`](pr-4288/) | `1da9ea140a09bb472a8308d496332e01c16e01a35fe2515149a3605fbe6e5ab4` |

Validate a public directory from its root with:

```bash
sha256sum -c SHA256SUMS
```
