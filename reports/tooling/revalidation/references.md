# References and documentation migration audit: PASS

Audited tracked repository at `a2600907a8013a5e890ce9c23c248f02f5f6887c`, with implementation `d02a4ce7b6b317d0115ba7dac344e6b22e775eb4`, and then reviewed the parent-owned clarification to `reports/release/README.md`. No remaining obsolete active helper invocation or maintained PowerShell/C#/Swift/Python implementation was found. The historical-index wording issue was corrected and rechecked. This audit agent changed no tracked files and reran no optional suites.

## Search coverage and results

I searched all tracked text, including README, docs, examples, tests, Cargo/pubspec/lockfiles, native/vendor, build helpers, CI, packaging, release evidence, developer setup, benchmarks, probes and generated-launch source. The first whole-tree pattern was:

```text
\.ps1\b|\.cs\b|\.csproj\b|\.swift\b|\.py\b|powershell|dotnet|csharp|\bswift\b|\bpython([0-9]+)?\b
```

`git grep -n -I -i -E` found 5,427 matching lines across 415 tracked files. I inspected every non-report match and classified report matches by content/provenance. A second search included `pwsh`, `powershell.exe`, `WindowsPowerShell`, `Add-Type`, `System.Management.Automation`, `runWindowsPowerShell`, `windows_powershell`, `csc.exe`, `dotnet`, and `C#`. I also used `git grep -n -I -F -f -` with all 38 exact removed helper paths from `reports/tooling/completion.json` plus old launcher/helper symbols. Outside reports, those removed-path hits occur only in the explicit old-to-new migration table (`docs/tooling-migration.md:43`).

An independent `git ls-files` suffix check found **zero** tracked `.ps1`, `.psm1`, `.cs`, `.csx`, `.csproj`, `.swift`, `.py`, or `.pyw` files. A read-only scan of current README/docs/example/benchmark/performance prose and CI found **52 unique Dart command paths** (`dart run` and `dart compile exe`); all resolve to files in the current tree. Git status was clean during the initial scan; the parent subsequently made the documentation clarification reviewed below and retained additional audit evidence.

## Active paths are Dart/Rust

- `bin/gpuidart.dart:3` imports the Dart command implementations directly. The command table includes doctor/build/run/check/package/verify/exec, and `tool/build_cli.dart:20` compiles the CLI to a native executable. README describes the Dart/Rust development toolchain, SDK checkout selection, native CLI output, Windows ZIP, Unix tarballs, and separate standalone package verifiers.
- External accessibility calls go through `tool/accessibility/client.dart:16` to `tool/native_probe/client.dart:12`, which builds/executes `gpuidart-native-probe` with Cargo. Mac AX/Metal, Linux AT-SPI and Windows UIA implementation lives in that Rust crate. No active Swift/Python/C# client invocation remains.
- `tool/src/windows_tool.dart:15` builds the Rust Windows helper and `:28` executes it directly. `tool/prepare_windows_release_checks.dart:43` compiles the Sandbox runner from Dart, and the generated `<LogonCommand>` calls `C:\GPUI-Input\sandbox_release_check.exe` (`:83`). The guest runner uses native `where.exe` for SDK absence checks. No generated PowerShell command is present.
- Windows packaging compiles the Dart standalone verifier and copies the Rust helper (`tool/src/windows_package.dart:65`). Generated README instructions use `.\verify.exe` (`:122`). Unix generated README instructions use `./verify`, including the documented `--runtime-only` mode (`tool/package.dart:177`). These match the shipped metadata and current verifier implementations.
- `pubspec.yaml`, root/native Cargo manifests, and the separate native-probe, Windows-helper and benchmark-driver Cargo manifests have no removed-language interpreter/compiler dependency. `tool/unix/Dockerfile.runtime:2` installs system runtime/display libraries, then invokes the native extracted verifier; it does not invoke a Python helper. Python packages in old/full OS inventories are installed-system records rather than maintained tooling requirements.
- Benchmark orchestration/analysis is Dart and the Windows driver is Rust. `benchmarks/README.md:5` names that architecture and documents current commands. `benchmarks/analyze.dart:210` mentions PowerShell only to preserve legacy singleton JSON shape; `benchmarks/driver/src/windows.rs:874` explains timing comparability with the old driver. Neither executes it.

## Intentional remaining references

| Category | Evidence and interpretation |
|---|---|
| PowerShell syntax fences | README, SDK/setup/release docs and benchmark/performance docs use Windows shell examples containing current Dart commands and environment assignments. A `powershell` Markdown fence does not imply a maintained `.ps1` helper. |
| CI shell wrappers | `.github/workflows/check.yml:21`, `performance.yml:47`, `release-packages.yml:82`, and `snapshot-experiment.yml:41` select `pwsh`. Bodies provide tool invocation, exit forwarding, MSVC linker selection or CRT/environment paths. Implementation remains in Dart/Rust; no script compilation or `Add-Type` remains. |
| Inventory rules and tests | `tool/source_inventory.dart:10` lists extensions it must recognize/reject. `test/source_inventory_test.dart:65` creates a synthetic vendor Python file and `:69` creates a temporary PowerShell fixture, then verifies committed maintained legacy source is rejected. `test/windows_preparation_test.dart:70` asserts generated configuration contains no PowerShell. These are tests of the migration rule. |
| Migration accounting | `docs/tooling-migration.md:38` and `reports/tooling/completion.json` retain the 38 deleted paths and replacement map. `reports/tooling/benchmark_migration.json:2` identifies the old reference revision and the parity method. Old analyzer values are evidence, not a tool dependency. |
| macOS system image inventories | 4,299 report matching lines contain system Swift framework/library paths or serialized image inventories. The retained macOS package runs actually load system libraries under `/usr/lib/` and `/System/Library/`; those are not repository Swift implementation or a Swift compiler requirement. |
| Runtime/build inventories | 258 matching report lines describe installed packages or historic container builds, including Python packages. They record actual environments rather than current helper invocations. |
| Earlier result/log captures | 653 matching report lines retain historical client commands, stderr, source paths, package manifests and Windows environment records. For example, old Linux AX reports preserve `tool/accessibility/linux.py` deprecation output. Current migration AX artifacts use the Rust client. Rewriting these logs would invalidate their evidentiary role. |
| Historical prose | 52 report Markdown matching lines describe old behavior or commands. `reports/ci/README.md:3` distinguishes current migration checks from earlier chronology; `:24` labels old `check.ps1` jobs historical. SDK preview and reload reports are dated 2026-09-25. Performance update-gate reports identify exact old trunk/head revisions; comparison reports are dated/capture-specific. The current migration document explicitly permits these original commands as recorded-revision evidence (`docs/tooling-migration.md:132`). |
| Retained observation source | Fifteen `.py.txt` attachments exist: 12 Linux IME drivers, 2 Windows IME drivers, and one reload-forensics attachment. IME READMEs explicitly date the experiments to 2026-09-26 and identify the environment/observer; reload investigation is dated 2026-09-25 with a subsequent source audit. Their reproducibility sections describe those experiments. No active build, CI, packaging, probe or setup path imports or invokes these attachments. They are not renamed active framework/tooling. |
| Vendored restart helper | `native/vendor/gpui-pre-windows-0.3.7/src/platform.rs:538` contains the upstream Windows restart method with an inline PowerShell wait/start snippet (`:544`), and uses `get_powershell` (`:571`). This is the existing vendored backend implementation allowed by the task's vendor exception. The inventory partition independently verified upstream provenance. No maintained GPUI-Dart native/launcher/lib/tool/benchmark caller invokes `.restart(...)`. Other vendor keyword hits are upstream comments/API descriptions. |
| Comparison fixtures and C ABI | Existing Flutter platform scaffolding, Shell/Solid comparison applications and the C ABI header are explicit unchanged comparison/interop scope, not migrated framework tooling. No C#/Python/Swift helper is hidden among them. |

The report category counts above are matching-line classifications, not language percentages or source-code counts. They are not used to exclude maintained implementation from the source inventory.

## Packaging/documentation accuracy

Current release/setup docs use the migrated helpers: `docs/windows-test-setup.md:7` prepares with Dart and explains the native Sandbox runner; Windows release checks use `verify.exe`; Unix release checks use the native verifier and describe the custom `--self-test` contract. `tool/src/windows_package.dart:119` labels the ZIP an evaluation package, describes its AOT runtime and native verifier, and disclaims a signed installer. `tool/package.dart:177` accurately describes package layout, tool-free app launch, default dependency inspection and runtime-only verification.

The macOS package manifest's ad-hoc/not-notarized state agrees with `docs/unix-release-checks.md` and `docs/tooling-migration.md:154`. Runtime-only mode is documented as retaining build-time dependency inspection while checking hashes/actual loaded images; it is not represented as a clean-machine certificate. Final completion docs distinguish the Windows/Linux historical clean-environment and IME observations from current source checks. Broad stable-release/physical-display/IME limits remain separate from this language migration.

## Historical-index clarification: resolved

At the audited commit, `reports/release/README.md:42` said the shared Dart launcher "now lets Windows PowerShell rebuild its module path" under `Current evidence`. The implementation was removed. The linked `reports/release/powershell-environment/README.md:3` already identified this as historical removed-launcher evidence. The index's present tense could mislead a reader scanning only that page.

The parent corrected this documentation issue. I reviewed `git diff -- reports/release/README.md`: the title is now `Release acceptance history`, lines 3-5 scope the page to `bb6a894`/`4fca314` in September 2026 and link current migration verification, and the former launcher sentence at line 46 is past tense and explicitly says the records describe the removed implementation. The change preserves the historical evidence and alters no implementation. The issue is resolved; no test rerun is warranted for this prose-only correction.

## Commands and scope limits

Audit commands: whole-tree tracked `git grep` expressions above; `git ls-files` suffix inventory; exact removed-path fixed-string search; `rg`/`Get-Content` source and prose inspection; an in-memory Python scan checking the 52 documented Dart command paths; and `git status --short`. Package/CI/runtime truth was checked against source and primary evidence in the completed macOS partition; the coordinator and other partition agents cover Windows/Linux and full source accounting. This partition did not claim fresh physical-host or clean-VM observations and did not repeat expensive already-passing tests.
