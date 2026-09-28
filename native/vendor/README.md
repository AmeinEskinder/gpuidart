# Pinned accessibility dependency corrections

The four AccessKit crates come from the existing lockfile, upstream commit
`c88605b96d04431f9c3c792464a0f2f253480e94`. They are path overrides in the workspace
Cargo.toml; dependency versions and feature sets stay the same. GPUI Kit keeps
its original git revision. GPUI 0.3.7 additionally has the focus hook below. Each UPSTREAM.json records the original registry archive checksum (verified
against the local cached crate), original copied-file hashes and patched hashes.
Only source, normalized manifest, README and provenance are copied. No build cache
is included. Licenses are the upstream MIT/Apache-2.0 alternatives, retained here
and included with evaluation packages; original source copyright headers remain.

[accessibility.patch](accessibility.patch) is the complete AccessKit source delta:

- Consumer: Row can be an item, and Table can contain selectable children. Actual
  selectability still requires selected state. This enables proper AXSelected and
  platform selection containers without changing Row/Table roles.
- Windows: selected-state Row exposes the existing SelectionItem provider and
  Click action mapping. Grid/Table coordinate patterns are still unavailable.
- AT-SPI: a disabled role without read-only support (Button) must not gain Enabled
  and Sensitive. This preserves the original read-only handling.

[cache-signals.patch](cache-signals.patch) corrects the Unix adapter's cache
signals. Each signal must carry **one struct argument**, as specified in the
[AT-SPI Cache interface](https://raw.githubusercontent.com/GNOME/at-spi2-core/main/xml/Cache.xml).
The original calls serialized the struct fields as separate arguments. A
single-element tuple keeps the struct intact. The external Linux D-Bus monitor
checks both AddAccessible and RemoveAccessible argument signatures from the owned
application PID during the Settings control sequence. It requires both signal
kinds and rejects malformed messages; query success alone is insufficient.

The real Settings/disabled/Watchlist platform probes are regression gates. Original
failures are retained under reports/accessibility. Do not remove these overrides
until an upstream version passes those same external-client checks on three OSes.
Do not edit registry caches. Regenerate provenance and review the patch separately
from upstream code if updating a crate. This is a maintained dependency patch,
not a claim that unmodified upstream already handles these cases.

## GPUI focus association

[focus.patch](focus.patch) adds one Window method to gpui-pre 0.3.7 (recorded against 0.3.6; both hunks apply to 0.3.7 at an offset): an existing
semantic node can use an editor's focus handle for accessibility while keeping
its presentation frame's original keyboard/tab tree. The host calls it during
prepaint, with the semantic node already present. It also routes the platform
Focus action to the actual editing state. This adds no tab stop and does not move
keyboard focus during rendering.

A rejected attempt changed the Input frame's tracked focus directly. That created
a duplicate tab stop and broke Settings Shift+Tab; the failed capture is retained.
The new hook separates the two registrations at the framework boundary. The
15-step Settings track and external Focus action are regression gates.

GPUI provenance is the original registry archive checksum (no VCS file was shipped
in that crate). Source, runtime resources, build script, docs, manifest and license
are copied; its development examples are omitted. The GPUI Apache-2.0 license and
source copyright notices are retained and copied into evaluation packages.
`tool/accessibility/verify_vendor.dart` checks all copied source and patched hashes
on every SDK check. `.gitattributes` preserves vendor bytes on every OS.


## Accessibility window bounds

[window-bounds.patch](window-bounds.patch), applied after focus.patch, calls the
existing platform `a11y_update_window_bounds` hook after adapter initialization
and whenever a window moves/resizes. Pinned GPUI defined this hook but never called
it. The Linux adapter consequently retained its default zero screen origin;
AT-SPI Component.GetExtents(SCREEN) returned client-relative positions. The terminal
hover verifier exposed the missing translation by moving the real pointer to those
reported coordinates. The external tooltip check is the regression gate. The
Windows/macOS default hook is a no-op; their adapters own the translation.


## Windows startup font enumeration

[font-collection.patch](font-collection.patch) changes one argument in the
vendored `gpui-pre-windows` 0.3.7 text system: the system font collection the
DirectWrite text system fetches once at startup no longer asks DirectWrite to
check for font changes first (`checkForUpdates = false`). DirectWrite still
detects installed fonts with some latency, and the lookup path that refreshes
the collection when a requested font is missing keeps its immediate check.
Measured in a fresh process on this machine (`startup_platform_costs`, the
ignored probe test in the native crate), the first enumeration took 85 to 163
ms with the check and 1 ms without it, which was most of the time between the
native run entry and window creation. The copy is a maintenance surface an
upstream change would remove: the call lives in Zed's `gpui_windows`
`DirectWriteTextSystem::new`, and either an upstream `false` or a platform
option to skip the startup check would let the vendored crate go. The crate is copied from the registry
archive with the same provenance rules as GPUI above; only `src`, the manifest,
the build script and the license are included.

## Windows command menu invocation

[menu-invoke.patch](menu-invoke.patch) retains InvokePattern on clickable command
MenuItems whose selected flag describes Kit's hover/keyboard highlight. The
original generic predicate suppressed Invoke for any selected-state property,
while the Windows adapter did not expose SelectionItem for MenuItem. The terminal's
Settings command thus had no action pattern despite its Click handler. Toggle and
expand/collapse items keep their existing patterns. The external terminal client
requires InvokePattern and verifies the resulting page change.

This follows Microsoft's [MenuItem control contract](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-supportmenuitemcontroltype):
a command item exposes Invoke; selection among options uses SelectionItem. It
changes no other role's pattern selection and makes no speech/navigation claim.
