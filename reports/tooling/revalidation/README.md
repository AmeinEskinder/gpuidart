# Migration completion revalidation

Seven audit partitions passed on 2026-09-30. Four native Codex agents covered the
partitions, with up to three running concurrently and a separate final auditor.
The coordinator independently checked source equality, artifact hashes, hosted
workflow results and the reference correction.

## Corrected-source verification

A later Windows CI run exposed a timing assumption in the live large-view test.
The [failure record](../large-view-ci-failure.md) explains the two-diagnostic race
and the reviewed test-only correction. All seven workflows, fresh native CLI
and release artifacts, and the local Windows platform probe then passed at
`c1eb6a992c8423c62fff9a80d80ea93c34a55dd9`. Current counts and provenance are in
[completion.json](../completion.json). The earlier partition reports below
preserve their original audited revisions.

The [independent refreshed evidence audit](corrected-evidence.md) passed all
422 source records, six artifact hashes, 48 package payloads, three sets of
412 provenance hashes, runtime/accessibility/reload receipts and the seven
live workflow results. No migration blocker was found.

## Earlier partition audits

Implementation revision: `d02a4ce7b6b317d0115ba7dac344e6b22e775eb4`.
Audited documentation/evidence revision:
`a2600907a8013a5e890ce9c23c248f02f5f6887c`.
All 422 recognized source records match between those revisions.

| Partition | Result |
| --- | --- |
| [Windows runtime and packaging](windows.md) | PASS |
| [macOS runtime and packaging](macos.md) | PASS |
| [Linux runtime, packaging and GPUI cache](linux.md) | PASS |
| [Source inventory and legacy removal](inventory.md) | PASS |
| [CI and verification commands](ci.md) | PASS |
| [References and documentation](references.md) | PASS |
| [Independent final evidence](evidence.md) | PASS |

The reference audit found one historical release-index sentence that described
the removed PowerShell launcher in the present tense. The coordinator corrected
its tense and labeled the page as historical. The reference and final auditors
reviewed that correction. Two explicit standalone Clippy invocations passed,
with one existing advisory warning each. Their receipts and logs are retained
under [completion](../completion/), with entries in [completion.json](../completion.json).

The seven initial Grok 4.6 audit attempts returned errors that the runner
classified as malformed output. Those attempts are not counted as reviews.
Native agents completed every partition; the original failure receipts remain
in the local `.cache/migration-revalidation` directory.

These reports preserve their audited revisions and scope. The documentation and
evidence follow-up changes no implementation source. Its commit identity and
final hosted checks are reported after the commit is created, avoiding a
self-referential evidence commit.
