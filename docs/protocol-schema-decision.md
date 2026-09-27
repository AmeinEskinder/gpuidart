# Wire schema generation decision

Decision for the settings-controls milestone: **skip code generation for now**.
Keep the handwritten codecs, bounds checks and ergonomic Dart API. This is a
maintenance choice, not a claim that generation cannot help.

## What would be generated

At the settings milestone, the adapter had ten node kinds: row, column, text,
button, input, table, checkbox, slider, select and confirmation dialog. Their wire contract also
includes styles, actions, table views and formats. Datasets and input commands
have separate transaction protocols. Rust serde models define accepted message
shapes; Dart wrappers encode them and validate caller values. Dart also validates
every received event before it changes pending-request state.

A generator would replace that duplicated structural work with one versioned
schema emitting Rust/Dart wire models, codecs and field documentation. It would
not replace the public Dart builders or native semantic validation.

## Options considered

| Option | Benefit | Cost and limit |
| --- | --- | --- |
| Keep current codecs | Small changes can be reviewed with their interaction and invalid-wire tests. No new build step. | Shapes, defaults and event names must still be updated on both sides. Documentation can drift. |
| Independent schema generates both languages | One source for tags, fields, optionality and structural docs. | Requires migrating existing snapshot, dataset and event models together; handwritten semantic checks still need to integrate with generated types. |
| Export a schema from Rust types and generate Dart | Keeps the receiving parser as the structural source. | Rust serde defaults, tagged variants and custom validation need generator policy. Exported schema alone cannot express the current contracts. |

The new code exposed concrete limits of structural generation:

* Slider bounds depend on representability at both endpoints in native f32.
* String limits count UTF-8 bytes, while input selection uses UTF-16 offsets and
  rejects boundaries inside surrogate pairs.
* A select value must occur in the same node's unique option IDs.
* Dialog dismissal emits one result tied to the opening revision; input writes
  reject composition and stale generations before changing retained state.

These remain native semantic checks with Dart validation where applicable,
regardless of schema choice. The retained failures also show genuine drift
risks: `input_control` was missing from the Dart trace operation decoder, and a
serde unit variant accepted unknown fields. A complete generator could prevent
some structural omissions. It would not fix focus restoration, deferred GPUI
callbacks, transaction ordering or IME conflicts. This milestone does not have
a second independent wire consumer or a supported external wire contract that
requires generated bindings. Migrating all codecs now is a separate project.

## Rules while generation is skipped

* Update the Rust parser/validator, Dart encoder/event validator, documentation
  and wire tests together when adding a field or event. Run both invalid-wire
  tests and real native interaction checks.
* Preserve semantic, fault-peer and cross-platform live tests if a generator is
  introduced later. Generated syntax is not an ownership or lifecycle test.
* Build Dart, native library and macOS launcher from the same source revision.
  ABI handshake remains version 1; the additive `gd_input` symbol is checked
  when controlled commands are used. The wire/diagnostic formats remain internal.
* Reopen this decision before exposing a stable external wire API, supporting
  another language client, or a broad catalog expansion. Use retained structural
  mismatch failures to evaluate benefit rather than just counting node kinds.

## Gate for a future generator

Use one explicitly versioned schema and deterministic generation. CI must reject
uncommitted generated differences. Prove encoded equivalence on accepted fixtures
and identical rejection on invalid fixtures, including defaults, unknown fields,
nullable values, non-finite numbers and Unicode boundaries. Preserve ergonomic
Dart wrappers and all transactional/interaction tests. Define ABI compatibility
and migration before accepting generated models as the source of truth.

Evidence: [control-catalog report](../reports/control-catalog/README.md),
`native/src/protocol.rs`, `native/src/input_control.rs`, `lib/src/nodes.dart`,
`lib/src/input_state.dart`, and the controls/input/fault-peer test suites.

Market-terminal update: tabs, radio groups and charts bring the count to thirteen;
menus and themes add snapshot properties. This work keeps the codec decision and
its rules above. Structural additions include matching native/Dart bounds and wire
tests, and the terminal exercises events through real hosts on all three platforms.
