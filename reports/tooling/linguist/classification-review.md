# Linguist classification audit

This retained review was written in the ignored local directory
`.cache/linguist-audit/classification/`. Relative artifact names in the original
review refer to that directory. Its machine-readable findings are retained as
[classification-inventory.json](classification-inventory.json) and
[classification-selected-blobs.tsv](classification-selected-blobs.tsv).
The temporary audit script and downloaded upstream documentation remain local.

**PASS — proposed classification is justified by file purpose.** No tracked files changed by this audit. The parent owns actual Linguist execution, attribute changes, and default-branch resolution.

Audited source: `68d1820df0ad9b656c1e79b5a0545cd25a1bec94` (alpha). All byte counts below are immutable Git blob bytes at this commit, not checkout sizes or inferred language percentages. Machine-readable evidence: `inventory.json`, `selected-blobs.tsv`, and reproducible read-only `audit_blobs.py`.

## Recommended root attributes

Use the eight attribute lines in `recommended-attributes.txt`. Extend the existing vendor line with `linguist-vendored`; keep its `-text` and all other existing byte/whitespace attributes. This is the smallest purpose-based set covering the agreed comparison-only statistics scope and correcting the current fixture default.

```gitattributes
native/vendor/** -text linguist-vendored
reports/** linguist-documentation
benchmarks/native/** linguist-detectable=false
benchmarks/dart/** linguist-detectable=false
benchmarks/flutter/** linguist-detectable=false
benchmarks/solid/** linguist-detectable=false
benchmarks/shell/** linguist-detectable=false
test/fixtures/** linguist-vendored=false
```

The comparison exclusions are an explicitly chosen scope policy. These applications remain first-party maintained source; they are neither vendored nor generated. Apply the same policy to Dart and Rust comparisons as to Flutter, Solid, and Shell. Preserve all benchmark orchestration, input drivers, build orchestration, analysis, tests, SDK code, and the C ABI header outside these five directories. No language is relabeled and no percentage target is used.

The vendor line documents an existing default: upstream Linguist already matches `native/vendor/`. The other rules change classification by purpose. Marking retained reports as documentation is more accurate than calling authored historical scripts generated.

## Scope and ownership evidence

| Scope | Files | Git bytes | Classification and reason |
| --- | ---: | ---: | --- |
| `native/vendor/` | 204 | 4,282,681 | Vendored upstream dependencies with narrow project patches and provenance |
| `benchmarks/native/` | 3 | 11,176 | First-party Rust reference application; comparison-only scope exclusion |
| `benchmarks/dart/` | 1 | 9,911 | First-party Dart comparison application; same exclusion |
| `benchmarks/flutter/` | 24 | 92,672 | Flutter comparison application and its Windows embedder/build files; same exclusion |
| `benchmarks/solid/` | 8 | 23,714 | Solid/GPUIX comparison application and its build bridge; same exclusion |
| `benchmarks/shell/` | 2 | 2,524 | QuickJS comparison application; same exclusion |
| `reports/` | 7,439 | 269,507,200 | Retained evidence and documentation, including historical source attachments |
| `test/fixtures/` | 2 | 6,957 | Restore detectability by removing automatic vendor classification |
| `native/include/gpuidart.h` | 1 | 3,433 | Keep counted: manually maintained public ABI |

Directory totals include data, binaries, and manifests that may already be excluded. They are not the expected change in Linguist's language totals. The five comparison directories total 38 files and 139,997 bytes.

### Vendored dependency provenance

`native/vendor/README.md` explains the pinned crates, licenses, source manifests, and maintained patch diffs. Four AccessKit copies are pinned to upstream commit `c88605b96d04431f9c3c792464a0f2f253480e94`; GPUI and its Windows platform copy are registry version 0.3.7. Six `UPSTREAM.json` records name original registry archive checksums and original/patched file hashes.

The independent Git-blob audit verified **all 186 recorded current files**, including seven patched files, against those manifests, with zero mismatches. This checks checked-in provenance consistency; it does not claim a new download/reverification of the six original registry archives. The copies contain 162 Rust files totaling 4,121,809 bytes and three HLSL files totaling 50,213 bytes. Narrow patches do not convert the surrounding upstream implementation into project-authored code. Retained patch files remain reviewable; do not mark the tree generated.

### Comparison apps and Solid build bridge

`benchmarks/README.md` describes five comparable 100,000-row workloads and their implementation differences. `benchmarks/build.dart` builds these executables; `benchmarks/package.dart` packages them; `benchmarks/src/process.dart` maps implementation names to these executable paths. This is application fixture scope, distinct from the retained Dart orchestration and Rust input driver.

`benchmarks/solid/build.ts` is **503 bytes of active authored build logic**. It builds `main.ts` into `dist/gpui-solid-comparison.exe` through the published `@gpuix/solid/bun-plugin`, handles build errors, and copies the published GPUIX native addon beside that comparator. `benchmarks/build.dart:77–83` invokes its package build command. It contains no GPUI-Dart SDK implementation or generic SDK packaging logic. It belongs to the Solid comparator scope and may receive `linguist-detectable=false` with that whole app; it must not be called generated or vendored. `main.ts` (178 bytes) and `app.tsx` (3,881 bytes) are also first-party app glue/workload code.

Flutter's Windows runner contains editable application configuration, including the comparator window title and geometry. Do not call the whole runner generated merely because Flutter provided its initial scaffold. Only these three files have clear generated-file declarations:

| Generated file | Bytes |
| --- | ---: |
| `benchmarks/flutter/windows/flutter/generated_plugin_registrant.cc` | 164 |
| `benchmarks/flutter/windows/flutter/generated_plugin_registrant.h` | 302 |
| `benchmarks/flutter/windows/flutter/generated_plugins.cmake` | 743 |

If comparison applications remain in language statistics instead, these three exact paths are justified `linguist-generated` candidates (1,209 bytes). Under the chosen comparison exclusion they add no statistics benefit and would additionally suppress diffs, so omit those optional rules from the minimal change.

### Reports and historical source attachments

The Linux Japanese IME report is explicitly dated 2026-09-26 and identifies its historical AOT/JIT revisions. Its archived driver text retains the commands used for that observation. Five `.sh.txt` files contain shell shebangs, so extension-only inventory misses them:

| Historical capture | Git bytes |
| --- | ---: |
| `reports/ime/linux-japanese-20260926/drivers/guest-env.sh.txt` | 313 |
| `reports/ime/linux-japanese-20260926/drivers/run_jit.sh.txt` | 281 |
| `reports/ime/linux-japanese-20260926/drivers/start-vm.sh.txt` | 497 |
| `reports/ime/linux-japanese-20260926/drivers/verify-clean-v2.sh.txt` | 1,212 |
| `reports/ime/linux-japanese-20260926/drivers/verify-clean.sh.txt` | 1,173 |

Their 3,476-byte sum matches the parent's actual Linguist 9.3.0 Shell result. They are retained observational documentation, not current maintained launch tooling. Reports also retain `.py.txt`, `.dart.txt`, logs, JSON, screenshots, and an observation patch. Historical authorship does not make them generated. `reports/** linguist-documentation` handles this evidence scope without changing capture bytes or hiding report diffs.

### Maintained fixtures and C header

Linguist's default `(^|/)[Tt]ests?/fixtures/` rule incorrectly classifies these project-owned test helpers as vendor:

- `test/fixtures/fault_host.rs` is a **6,325-byte** handwritten ABI peer for failure injection, timeouts, malformed events, callback ownership, and shutdown. `tool/build_test_fixtures.dart` compiles it; `test/host_fault_test.dart` and `test/tracing_test.dart` consume it.
- `test/fixtures/companion_client.dart` is **632 bytes**. `test/companion_lifecycle_test.dart` runs it as a subprocess to check hung/exited Unix companion startup and owned-child cleanup.

Restoring them with `linguist-vendored=false` makes the maintained test implementation count. The exact Rust blob size is 6,325 bytes; a prior parent message's 6,785-byte figure is not this file's Git size.

`native/include/gpuidart.h` is a maintained C ABI contract, with typed declarations and ownership/threading comments. Its history includes changes for operation updates, secondary windows, compatibility, and shutdown. No generator was found. Declarations-only code is still source. Leave all its Linguist attributes unset; do not label it generated, vendor, documentation, or undetectable merely to obtain only Dart/Rust totals.

## Existing attributes and inventory limitations

All four tracked `.gitattributes` files were inspected: root; `reports/control-catalog/`; `reports/ime/linux-japanese-20260926/`; and `reports/performance/`. They currently set only byte preservation/whitespace behavior. Their exact contents are retained in `inventory.json`; none conflicts with the proposed Linguist classifications.

`tool/source_inventory.dart` is useful scope evidence but explicitly not a GitHub language detector. It omits HLSL and CMake, treats final filename extensions as the language basis, and labels the C header as interface. Consequently it misses shebang-detected archived Shell and cannot justify excluding the maintained ABI. Ownership, current call sites, and documented purpose were checked separately here.

## Primary Linguist sources and default-branch issue

Official Linguist recognizes separate documentation, vendor, generated, and detectability attributes. Documentation and vendor exclusions affect statistics; generated classification also suppresses diffs. Paths are relative to the attribute file, and local tests need a committed tree. See [official overrides](https://github.com/github-linguist/linguist/blob/5fbdfcb8133be2bed88bf3ce62b2335f50474525/docs/overrides.md) and [default vendor rules](https://github.com/github-linguist/linguist/blob/5fbdfcb8133be2bed88bf3ce62b2335f50474525/lib/linguist/vendor.yml). Copies of these and detection sources are retained beside this report.

GitHub computes its repository language summary on the default branch in background analysis. See [official detection process](https://github.com/github-linguist/linguist/blob/5fbdfcb8133be2bed88bf3ce62b2335f50474525/docs/how-linguist-works.md). Independent `gh api` checks during this audit found default `main` at `111a5bfc2e609118954bd48bd295f01101e3e9a7`; `alpha` was 107 commits ahead and zero behind. Old API proportions therefore describe a different source revision. Attribute correctness and default-branch selection are separate questions. Parent owns branch resolution and reproducible before/after Linguist results.

## Parent's concrete attribute patch

After saving the classification findings, the parent applied the proposed eight rules. I inspected the exact `.gitattributes` diff and `git check-attr` output. The patch matches the approved scopes and preserves existing `-text` rules. Representative checks confirm vendor set, report documentation set, Solid/Dart comparator detectability false, test fixture vendor false, and no override on the C ABI header or retained benchmark build/driver paths. The visible tracked changes (`.gitattributes` and the parent's `reports/tooling/linguist/`) were parent-owned; this agent wrote only this ignored classification directory.
