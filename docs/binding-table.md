# Binding table: GPUI Kit components against gpuidart node kinds

What of the pinned GPUI Kit (`gpui-component` 0.7.0 at `0c830f4d`) an
application can reach from Dart, kind by kind, and what it cannot. The
left column lists every module of the Kit component crate; the middle
column names the gpuidart node or API that binds it, or the reason it is
not bound. "Planned" marks the kinds the catalog work adds next; "not
bound" marks a component an application cannot reach today; "host" marks
infrastructure the adapter uses on the application's behalf without a node.

| Kit module | gpuidart | Notes |
| --- | --- | --- |
| accordion | not bound | Collapsible sections. |
| alert | not bound | Callout boxes; `UiText` with a style approximates one. |
| attachment | not bound | File attachment chips. |
| avatar | not bound | `UiImage` shows a picture; the fallback initials and status dot are not bound. |
| badge | not bound | |
| breadcrumb | not bound | |
| bubble | not bound | Chat bubbles. |
| button | `UiButton` | Click events, tooltip, styles. |
| carousel | not bound | |
| chart | `UiChart` | Read-only single-series line and bar projections over a dataset view, at most 512 points. |
| checkbox | `UiCheckbox` | Value ownership with `checkbox_change`. |
| clipboard | not bound | Copy buttons. |
| collapsible | not bound | |
| color_picker | not bound | |
| combobox | planned | A select with a typed filter over its options. |
| command | not bound | Command palette. |
| component_traits | host | |
| description_list | not bound | |
| dialog | `UiConfirmDialog` | Title, message and two buttons; arbitrary dialog content is not bound. |
| dock | not bound | Dockable panel layouts. |
| element_ext | host | |
| empty | host | |
| form | not bound | `UiColumn` and `UiRow` lay out forms without it. |
| global_state | host | |
| group_box | not bound | |
| highlighter | host | Syntax colouring inside inputs. |
| history | host | |
| hover_card | not bound | |
| icon | `UiIcon` | Lucide icons by name from the bundled catalog. |
| index_path | host | |
| input | `UiInput` | Single-line text, native-retained or controlled; number, OTP and multi-line inputs are not bound. |
| inspector | host | Development tool. |
| kbd | not bound | Keyboard shortcut chips. |
| label | `UiText` | |
| link | not bound | `openUrl` performs the action without a link control. |
| list | `UiList` | A virtualized list over one dataset column with record IDs. |
| marker | host | |
| menu | `UiMenu`, `UiMenuButton`, `UiTable.contextMenu` | Application menus, popup menus on a button, record-bound row commands. |
| message, message_scroller | not bound | Chat transcripts. |
| native_menu | `UiMenu` | The macOS menu bar; Kit's menu bar on Windows and Linux. |
| notification | not bound | Toasts. |
| pagination | not bound | |
| plot | `UiChart` | Through the chart. |
| popover | `UiPopover` | A labelled trigger button and an anchored popup holding a subtree; `popover_change` event. |
| progress | `UiProgress` | Determinate or indeterminate. |
| questionnaire | not bound | |
| radio | `UiRadioGroup` | |
| rating | not bound | |
| resizable | `UiPanes` | Panes on one axis with drag handles, retained sizes and a `panes_resize` event. |
| root | host | The window root the adapter renders into. |
| scroll | `UiScroll` | Bounded scroll containers with retained offsets. |
| searchable_list | not bound | |
| select | `UiSelect` | |
| separator | `UiSeparator` | |
| setting | not bound | Settings page scaffolding. |
| sheet | `UiSheet` | A sheet from any window edge holding a subtree, open by publication; `sheet_close` event. |
| shimmer, skeleton, spinner | not bound | Loading placeholders; an indeterminate `UiProgress` is the one bound loading indicator. |
| sidebar | not bound | |
| sizing | host | |
| slider | `UiSlider` | |
| status_bar | not bound | |
| stepper | not bound | |
| styled | host | Kit's style helpers back `UiStyle`. |
| switch | `UiSwitch` | |
| tab | `UiTabs` | |
| table | `UiTable` | Dataset-backed with views, formats, selection and row commands. |
| tag | not bound | |
| text | planned | Rich text (markdown) through Kit's text view. |
| theme | `UiTheme` | Light and dark palettes with bounded token overrides. |
| time | `UiDatePicker` | The calendar date picker; the time field is not bound. |
| title_bar | not bound | Custom title bars. |
| toolbar | not bound | |
| tooltip | `UiButton.tooltip` | Buttons only. |
| touch_selection | host | Platform text selection. |
| tree | `UiTree` | Labelled items with stable IDs, expansion and one selection; `tree_select` and `tree_expand` events. |
| virtual_list | `UiList`, `UiTable` | Through the list and the table. |
| window_border, window_ext | host | |

Beyond the component crate, gpuidart binds Kit's base animation
(`UiStyle.animation`), its calendar (through the date picker) and its
window and lifecycle; `UiCanvas`, `UiStack`, `UiColumn` and `UiRow` are
gpuidart's own over GPUI's elements. Twenty-eight node kinds reach about a
third of the component catalog; the planned two close the largest gaps an
application notices (combobox, rich text), and the rest stay reachable
only by extending the adapter.
