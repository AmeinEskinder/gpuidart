# Pinned AccessKit adapter corrections

These three crates come from the existing lockfile, upstream commit
`c88605b96d04431f9c3c792464a0f2f253480e94`. They are path overrides in the workspace
Cargo.toml; GPUI and GPUI Kit pins, dependency versions and feature sets stay the
same. Each UPSTREAM.json records the original registry archive checksum (verified
against the local cached crate), original copied-file hashes and patched hashes.
Only source, normalized manifest, README and provenance are copied. No build cache
is included. Licenses are the upstream MIT/Apache-2.0 alternatives, retained here
and included with evaluation packages; original source copyright headers remain.

[accessibility.patch](accessibility.patch) is the complete source delta:

- Consumer: Row can be an item, and Table can contain selectable children. Actual
  selectability still requires selected state. This enables proper AXSelected and
  platform selection containers without changing Row/Table roles.
- Windows: selected-state Row exposes the existing SelectionItem provider and
  Click action mapping. Grid/Table coordinate patterns are still unavailable.
- AT-SPI: a disabled role without read-only support (Button) must not gain Enabled
  and Sensitive. This preserves the original read-only handling.

The real Settings/disabled/Watchlist platform probes are regression gates. Original
failures are retained under reports/accessibility. Do not remove these overrides
until an upstream version passes those same external-client checks on three OSes.
Do not edit registry caches. Regenerate provenance and review the patch separately
from upstream code if updating a crate. This is a maintained dependency patch,
not a claim that unmodified upstream already handles these cases.
