# GitHub Linguist forensic audit

The reported 43.2% Dart, 43.2% Rust and 9.7% PowerShell measured the old default
branch `main`. They did not measure the migrated `alpha` branch.

At the start of this audit on 2026-09-30, the commits were:

- Default `main`: `111a5bfc2e609118954bd48bd295f01101e3e9a7`.
- Migrated `alpha`: `68d1820df0ad9b656c1e79b5a0545cd25a1bec94`.
- `alpha` was 107 commits ahead of `main`, with no divergent commits on `main`.

GitHub's language API has no supported branch parameter. A query with
`ref=alpha` returned the same repository totals. GitHub documents that language
statistics update from the default branch. Selecting a branch in the code view
does not select a different repository language calculation.

## Every reported byte reconciles

Actual Linguist reproduced all ten live API totals. The Git blob sizes of every
file in its breakdown independently sum to the same totals.

| Language | GitHub bytes | Counted files | Exact share, rounded to two decimals |
| --- | ---: | ---: | ---: |
| Dart | 510,589 | 123 | 43.23% |
| Rust | 509,793 | 55 | 43.16% |
| PowerShell | 114,870 | 27 | 9.73% |
| C# | 16,266 | 3 | 1.38% |
| Python | 9,581 | 2 | 0.81% |
| Swift | 7,637 | 2 | 0.65% |
| TypeScript | 4,562 | 3 | 0.39% |
| Shell | 3,476 | 5 | 0.29% |
| JavaScript | 2,496 | 1 | 0.21% |
| C | 1,802 | 1 | 0.15% |
| Total | 1,181,072 | 222 | 100% |

The live response is [github-before.json](github-before.json). The complete
Linguist breakdown is [main-linguist.json](main-linguist.json). Every counted
path, language, byte size and Git object is in
[main-counted-files.tsv](main-counted-files.tsv).

The four legacy languages comprise 34 files and 148,354 bytes. All are
project-owned implementation, tests or tooling on old `main`. None is vendored
or generated. The benchmark scripts are owned orchestration and analysis,
including the scripts that invoke comparison applications.

[The per-file audit](legacy-files.md) gives each file's purpose, execution route,
ownership, classification, disposition and replacement. The same records are
available as [TSV](legacy-files.tsv) and [JSON](legacy-files.json), with exact
blob IDs and caller locations. No legacy script was executed for this audit.

Case-insensitive enumeration found no `.psm1`, `.psd1` or `.csproj` on old
`main`. It found no `.ps1`, `.psm1`, `.psd1`, `.cs`, `.csproj`, `.swift` or `.py`
on migrated `alpha`. All 34 old implementations already have their replacements
on `alpha`; they must stay removed when integrating that branch. Reclassifying
the old files as vendor or generated code would be incorrect.

The migration's earlier 38-file count used baseline `9f825a2`, which also had
`benchmarks/calibrate-wheel.ps1`, `benchmarks/report-pair.ps1`,
`benchmarks/resume-series.ps1` and `tool/performance/run_update_gate.ps1`.
Those four files were never part of the old default branch's 34-file total.

## Existing classifications and precise corrections

Before this change, all four tracked `.gitattributes` files controlled only
byte preservation or whitespace. None contained a Linguist override.

Linguist already excluded `native/vendor` through its built-in vendor rule.
On old `main`, 4,153,612 Rust bytes minus 3,637,494 vendor bytes and the 6,325-byte
fault fixture produce the reported 509,793 bytes. The Dart fixture accounts for
the difference between 511,221 raw Dart bytes and 510,589 counted bytes.

The root attributes now express these scopes:

| Scope | Attribute | Reason |
| --- | --- | --- |
| `native/vendor/**` | `linguist-vendored` | Recorded upstream crates with source hashes and narrow documented patches. Already excluded automatically. The existing `-text` rule remains. |
| `benchmarks/native/**`, `benchmarks/dart/**`, `benchmarks/flutter/**`, `benchmarks/solid/**`, `benchmarks/shell/**` | `linguist-detectable=false` | Five comparison workloads, excluded consistently across languages. These are first-party fixtures, not vendored or generated code. |
| `reports/**` | `linguist-documentation` | Retained observations, verification receipts and historical source captures. Five shell captures were incorrectly contributing 3,476 bytes. |
| `test/fixtures/**` | `linguist-vendored=false` | The handwritten failure-injection host and companion lifecycle client are project-owned test implementations. Both now count. |

All SDK implementation, examples, tests, benchmark orchestration, analysis and
the native benchmark driver remain counted. The Solid `build.ts` belongs solely
to its comparator. It builds the Solid entry point through the required Bun
plugin and stages that comparison application's addon.

The maintained C ABI header `native/include/gpuidart.h` remains counted as C.
No `linguist-generated` or language-wide hiding rule was added. The three
generated Flutter plugin files need no separate rule because their comparison
application already has an explicit scope.

[classification-changes.tsv](classification-changes.tsv) enumerates every file
whose inclusion changes. No source content is changed or deleted by these
attributes.

## Actual Linguist result on migrated source

| Language | Before attributes | After attributes | Final bytes |
| --- | ---: | ---: | ---: |
| Dart | 47.43% | 47.74% | 888,069 |
| Rust | 50.27% | 52.07% | 968,526 |
| C | 0.22% | 0.18% | 3,433 |
| C++ | 1.00% | 0% | 0 |
| CMake | 0.54% | 0% | 0 |
| TypeScript | 0.24% | 0% | 0 |
| JavaScript | 0.13% | 0% | 0 |
| Shell | 0.18% | 0% | 0 |
| PowerShell, C#, Python, Swift | 0% | 0% | 0 |

The new denominator is 1,860,028 bytes across 242 files. This is actual Linguist
output, including the C interface. It differs from the maintained Dart/Rust-only
denominator in the earlier source inventory.

The complete results are [alpha-before.json](alpha-before.json) and
[alpha-after.json](alpha-after.json), with per-file byte attribution in
[alpha-before-counted-files.tsv](alpha-before-counted-files.tsv) and
[alpha-after-counted-files.tsv](alpha-after-counted-files.tsv).

## Reproduction and version

The executable reports `github-linguist 9.3.0`. The official image is pinned by
digest because its mutable tag and metadata do not identify its installed gem
reliably:

```text
ghcr.io/github-linguist/linguist@sha256:d84fcd094a967a128e73661293904758a6e6c383acb0e7ac289154ce160787f5
```

The audit used a read-only bare clone and the official command:

```sh
github-linguist /repo --rev COMMIT --breakdown --json
```

The before commits are specified above. The proposed attributes were tested in
an isolated audit commit, `fb7d1f04503ba48e556ac9abb975826442b5d89b`, whose only
change from `68d1820` was the root `.gitattributes`. Its exact after breakdown
is retained here. Git blob sizes, not Windows checkout sizes, were reconciled.

The live GitHub language bar can change only after its default branch points to
the migrated source with these attributes. Pushing attributes to `alpha` alone
does not update a bar that still measures old `main`. At this audit stage,
default-branch resolution and live API verification are pending. Their result
must be recorded before claiming that the GitHub language bar has changed.

Primary references:

- [GitHub repository languages](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-repository-languages).
- [Linguist operation on GitHub](https://github.com/github-linguist/linguist/blob/main/docs/how-linguist-works.md).
- [Linguist overrides](https://github.com/github-linguist/linguist/blob/main/docs/overrides.md).
- [Linguist command-line usage](https://github.com/github-linguist/linguist#command-line-usage).
