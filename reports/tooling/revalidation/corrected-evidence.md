PASS

Independent refreshed evidence review of source c1eb6a992c8423c62fff9a80d80ea93c34a55dd9. No material mismatch or migration blocker found. This report supersedes the earlier evidence audit for the corrected source; it does not pre-attest the coordinator's upcoming documentation/evidence commit.

Source and correction

- HEAD and live origin alpha both resolve to c1eb6a992c8423c62fff9a80d80ea93c34a55dd9. Current working changes are documentation/evidence. No application source is modified.
- Independently read the Git tree and all recognized Git source blobs using git ls-tree -rlz and git cat-file --batch. All 422 inventory paths, objects, byte counts, and line counts match the committed source. Maintained Dart is 175 files, 888069 bytes, 26907 lines, or 47.83321079718517%. Maintained Rust is 66 files, 968526 bytes, 26506 lines, or 52.16678920281483%. completion.json architecture totals equal source-composition.json. The source delta from the previous audit is the 763-byte, 11-line reduction in test/native_host_test.dart.
- Inspected the precise test correction at test/native_host_test.dart:692 and the failed Windows log at .cache/migration-revalidation/final/windows/run.log:962. The old assertion expected R149999 after the sort had already completed and returned R0. Two separate diagnostics could observe different phases. The correction removes those timing-dependent pending/old-order checks and comments. It retains settled pending=false, final ascending/descending order, events, job counts, revisions, sequential edit results, zero dataset copies, and small replacement behavior.
- Inspected native/src/ui/tests.rs:3074. Its controlled executor still verifies the initial pending index, waiting edits, acknowledgement order, and superseded jobs. Inspected Dart settled-event delivery and the pendingViews/completer handling in lib/src/host.dart. The correction does not weaken the settled contract or alter runtime code. Fresh raw logs show both the controlled native test and corrected live Dart test pass on Windows, macOS, and Linux.

Artifacts and provenance

- Recomputed SHA-256 and size of all six CLI/package artifacts referenced by the refreshed completion report. Every value matches the retained artifact bytes.
- Read all three release archives and verified every manifest payload hash and size: Windows 16 files, macOS 17, Linux 15. Raw verification reports exactly equal their refreshed committed JSON files. Manifest build provenance equals the build provenance carried by verification.
- Independently checked all 412 source entries in each package against Git blobs at c1eb6a9. All match. Windows has 208 expected CRLF conversions; Unix uses Git blob bytes directly. Recomputed all three aggregate source_sha256 values successfully. Every package reports source_dirty=false and exact c1eb6a9; every extracted AOT application self-test passes.
- Inspected native CLI headers: PE on Windows, Mach-O on macOS, ELF on Linux. Unix archives each contain one executable with executable mode bits. Queried all nine hosted artifact records live using gh api. Their IDs, sizes, download URLs and expiry times match completion.json; each belongs to package run 36663543515 at c1eb6a9 and is unexpired.

Runtime and raw evidence

- All three refreshed platform JSON files exactly equal raw results. Their source.stdout.log files record c1eb6a9. Windows has 12 checks, Linux 16, macOS 14. No timeout, error, or input driver failure appears. The only nonzero exits are the documented macOS worker/direct-Dart main-thread rejections. Companion JIT/AOT/reload passes.
- Retained checkpoints prove Linux matching input, one click, resized rendering and loop return; Windows AOT callbacks 1 and 7, 22 heartbeat ticks, resized rendering and exit 0; macOS companion AOT resized rendering, applied state, 17 ticks and native exit 0.
- All 24 raw accessibility results pass. Per target, controls record 9 steps, settings 15, watchlist 7, terminal JIT 15, terminal AOT 15. Disabled state, platform spike and terminal reload also pass. Refreshed Linux cache JSON exactly matches raw evidence: 50 additions, 47 removals, no invalid events.
- Refreshed CLI reload reports exactly match raw records on all targets, with file-save reload, native close stopping the launcher, and exit 0. Windows failure-case evidence, Linux clean-container verification and macOS runtime-only verification also exactly match raw records and pass. Linux retains ldd inspection with runtime_only=false. macOS runtime_only=true is explicitly a hosted developer-machine check, not clean-machine or notarization proof.

CI and counts

Independently queried gh run view for all seven fresh runs, including every job. Each is completed/success with exact headSha c1eb6a992c8423c62fff9a80d80ea93c34a55dd9:

- Windows SDK 36663515995
- macOS SDK 36663516055
- Linux SDK 36663515974
- Accessibility 36663536464
- Unix lifecycle 36663515949
- Platform 36663539929
- Packages 36663543515

Read the fresh SDK and lifecycle logs. Counts match completion.json: Windows 111 native plus two ignored timing probes, 141 Dart, 3 snapshot, 9 benchmark tests; each Unix target 115 native plus one ignored timing probe, 116 headless Dart with two Windows-only skips, 29 window Dart, 3 snapshot, 9 benchmark and 7 lifecycle tests. Formatting reports 177 files with zero changes; Dart analysis reports no issues.

Existing Clippy receipts remain applicable. git diff d02a4ce HEAD -- '*.rs' '*Cargo.toml' '*Cargo.lock' is empty. The retained receipts honestly state their original revisions and disclose existing warnings, including the separately retained helper/driver receipts. No unchanged expensive suite was rerun for this review.

Commands and limits

Used git show, git diff, git status, git rev-parse, git ls-remote, git ls-tree, git cat-file --batch, gh run view, gh api for artifact metadata, targeted rg and source reads, plus independent in-memory Python JSON, archive, hash and count inspection. No tracked file was edited. The current documentation/evidence refresh is awaiting coordinator integration. The coordinator must commit, push, verify source equality to c1eb6a9 and confirm final commit workflows before claiming the final branch is clean and checked.

Physical monitor and human IME behavior, clean Mac deployment, public notarization, and full comparison-application rebuilding remain outside the declared verification scope. These limitations are disclosed and do not represent a remaining legacy implementation.
