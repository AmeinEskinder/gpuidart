# MIT release packages, 2026-09-26

The owner explicitly selected MIT. Commit
`4fca3147806878bd3b8fbcff0a92676b8452727e` adds the [project license](../../../LICENSE),
declares MIT in each first-party Cargo package, and includes `LICENSE` in every
platform archive and its file/source hash manifests. Dependency terms remain
separate. The text follows the [MIT License](https://opensource.org/license/mit).

## Verification

- GitHub's repository license endpoint recognizes SPDX `MIT`.
- Dart analysis and PowerShell parsing passed. Cargo metadata reports MIT for
  all four first-party crates.
- The Windows package was built from clean committed source through the Dart
  launcher. Its MIT file matches the repository byte for byte. The archive also
  includes GPUI Kit's Apache-2.0 text and the Dart runtime license. The Dart SDK
  locator resolves the actual runtime when `dart` is a Flutter wrapper.
- [Local Windows verification](local-verification.json) and a new
  [fresh Sandbox check](clean-windows/verification.json) passed for the same ZIP.
  The [guest inventory](clean-windows/environment.json) reports no developer SDK
  commands and only Microsoft Remote Display Adapter. Loaded WARP modules
  confirm software rendering. Common Controls v6 and PerMonitorV2 at DPI 120
  passed. The automatic logon command ran once; no manual duplicate was started.
- Both [Unix package jobs](https://github.com/AmeinEskinder/gpuidart/actions/runs/36214976228)
  passed. Retained reports cover [macOS](unix/macos/verification.json), its
  [runtime-only verifier](unix/macos/runtime-only.json), [Linux X11](unix/linux/verification.json)
  and a [fresh Linux runtime container](unix/linux/clean-container/verification.json).
  The downloaded archives contain the exact repository MIT file and matching
  file/source manifest entries. Each reports clean source at `4fca314`.
- [All six workflows](ci.json) passed at the implementation commit: Windows,
  macOS and Linux SDK checks, Unix lifecycle, platform probes and Unix packages.

## Archive identities

| Target | Archive | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Windows x64 | `WatchlistMit4fca314-windows-x64.zip` | 11,718,871 | `e5b66c8b3dfafc5af04bd85f56f572acc5bf69a41e2c50b6f823def67476d87b` |
| macOS ARM64 | `Watchlist-macos-arm64.tar.gz` | 13,675,799 | `68ea31c9e3978bc2d156eaede1ab7fdd72ff9207aba061a3336862f4c606b807` |
| Linux x64 | `Watchlist-linux-x64.tar.gz` | 23,798,704 | `42a071c884249a188daaf16648b0336619e0ee13492f78b1c8c40ccea5823a62` |

See [Windows metadata](windows-artifact.json) and [Unix metadata](unix-artifacts.json).
The MIT file SHA-256 is
`09a57f07cfced3b344cbef7a277da22eb3f0bddfeae5c742d989e9c0827d98a2`.
The current native DLL hash differs from the previous package after rebuilding;
this report does not claim identical binaries. Application and native source
behavior were not changed by the license milestone.

## Remaining gates

Licensing is closed. These package passes do not establish human IME behavior,
physical display behavior, clean Mac/Linux desktop launch, or macOS Developer ID
distribution and notarization. The original `attempt-023eef4` reload observation
remains unlocalized. Existing failure reports are retained.

The desktop helper still failed to connect to its native pipe. No human IME
results were supplied or inferred. The prepared host observation sheet is
`build/manual-checks/4fca314-windows-ime.md`; every result remains pending.
The repository Actions secret list was empty. That inventory does not inspect
organization/environment credentials or prove that the owner lacks a Developer ID.
See [the external-check record](external-checks.json).

The accepted Sandbox run is
`build/release-checks/20260926-033124-d40b4635`. Its guest was stopped after the
reports were retained. The full stable-release goal remains open.
