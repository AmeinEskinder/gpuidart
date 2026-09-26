import 'dart:async';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/tracing.dart';

final class Preferences {
  const Preferences({
    this.name = 'Dart user',
    this.notifications = true,
    this.accent = 'ocean',
    this.spacing = 16,
  });
  final String name;
  final bool notifications;
  final String accent;
  final double spacing;
  Preferences copyWith({
    String? name,
    bool? notifications,
    String? accent,
    double? spacing,
  }) => Preferences(
    name: name ?? this.name,
    notifications: notifications ?? this.notifications,
    accent: accent ?? this.accent,
    spacing: spacing ?? this.spacing,
  );
  Map<String, Object> toJson() => {
    'name': name,
    'notifications': notifications,
    'accent': accent,
    'spacing': spacing,
  };
}

/// Preferences are kept in memory. Native controls provide the editing state;
/// this object owns the draft, saved values, validation and reset decision.
final class SettingsApplication {
  SettingsApplication._();
  late final GpuiHost host;
  late final StreamSubscription<GpuiEvent> _subscription;
  Future<void> _pending = Future.value();
  UiInputState? _nameState;
  bool _closing = false;
  Preferences draft = const Preferences();
  Preferences saved = const Preferences();
  String section = 'general';
  String status = 'Changes stay in this application. Apply to save the draft.';
  Object? failure;
  final eventCounts = <String, int>{};

  static Future<SettingsApplication> open({GpuiTrace? trace}) async {
    final app = SettingsApplication._();
    app.host = await GpuiHost.openView(
      app.build,
      trace: trace,
      window: const GpuiWindowOptions(
        title: 'Preferences',
        width: 780,
        height: 670,
      ),
    );
    app._subscription = app.host.events.listen((event) {
      if (event.type == 'closed') {
        app._closing = true;
        return;
      }
      if (event.type == 'error') {
        app.failure = StateError(event.toString());
        return;
      }
      if (!const [
        'input',
        'click',
        'checkbox_change',
        'slider_change',
        'select_change',
        'dialog_result',
      ].contains(event.type)) {
        return;
      }
      app.eventCounts.update(event.type, (n) => n + 1, ifAbsent: () => 1);
      app._pending = app._pending
          .then((_) async {
            if (!app._closing) {
              await app._handle(event);
            }
          })
          .catchError((Object error) {
            app.failure = error;
          });
    });
    try {
      await app._restoreName(app.draft.name);
      return app;
    } catch (_) {
      await app.close();
      rethrow;
    }
  }

  Future<void> get idle => _pending;
  bool get dirty =>
      draft.name != saved.name ||
      draft.notifications != saved.notifications ||
      draft.accent != saved.accent ||
      draft.spacing != saved.spacing;
  UiColor get accentColor => UiColor.hex(switch (draft.accent) {
    'forest' => '#16A34A',
    'orchid' => '#9333EA',
    _ => '#2563EB',
  });

  UiNode build() => UiColumn('settings', [
    const UiText(
      'heading',
      'Preferences',
      style: UiStyle(fontSize: 28, fontWeight: UiFontWeight.semibold),
    ),
    const UiText(
      'intro',
      'Make this workspace your own.',
      style: UiStyle(foreground: UiColor.token(ThemeToken.mutedForeground)),
    ),
    UiRow('navigation', [
      UiButton('general', 'General', style: _navStyle('general')),
      UiButton('appearance', 'Appearance', style: _navStyle('appearance')),
    ]),
    if (section == 'general')
      UiColumn('general-form', [
        const UiText(
          'general-title',
          'Your profile',
          style: UiStyle(fontSize: 20, fontWeight: UiFontWeight.semibold),
        ),
        const UiText('name-label', 'Display name'),
        const UiInput(
          'name',
          controlled: true,
          placeholder: 'Your display name',
          style: UiStyle(width: UiSize.full),
        ),
        UiCheckbox(
          'notifications',
          'Enable workspace notifications',
          checked: draft.notifications,
          disabled: draft.name.trim().isEmpty,
          style: const UiStyle(
            foreground: UiColor.token(ThemeToken.foreground),
          ),
        ),
        const UiText(
          'notification-note',
          'A display name is required to enable notifications.',
          style: UiStyle(foreground: UiColor.token(ThemeToken.mutedForeground)),
        ),
      ], style: _card),
    if (section == 'appearance')
      UiColumn('appearance-form', [
        const UiText(
          'appearance-title',
          'Workspace appearance',
          style: UiStyle(fontSize: 20, fontWeight: UiFontWeight.semibold),
        ),
        const UiText('accent-label', 'Accent color'),
        UiSelect(
          'accent',
          options: const [
            UiSelectOption('ocean', 'Ocean'),
            UiSelectOption('forest', 'Forest'),
            UiSelectOption('orchid', 'Orchid'),
          ],
          selected: draft.accent,
          placeholder: 'Choose an accent',
          style: const UiStyle(width: UiSize.px(260)),
        ),
        UiText('spacing-label', 'Preview spacing: ${draft.spacing.toInt()} px'),
        UiSlider(
          'spacing',
          min: 8,
          max: 24,
          step: 2,
          number: draft.spacing,
          style: UiStyle(width: const UiSize.px(320), foreground: accentColor),
        ),
        UiColumn(
          'preview',
          [
            UiText(
              'preview-title',
              'Workspace preview',
              style: UiStyle(
                fontWeight: UiFontWeight.semibold,
                foreground: accentColor,
              ),
            ),
            const UiText(
              'preview-body',
              'The chosen accent and spacing apply here.',
            ),
          ],
          style: UiStyle(
            padding: List.filled(4, draft.spacing),
            gap: draft.spacing / 2,
            borderColor: accentColor,
            borderRadius: 8,
            background: const UiColor.token(ThemeToken.background),
          ),
        ),
      ], style: _card),
    UiText(
      'status',
      status,
      style: const UiStyle(
        foreground: UiColor.token(ThemeToken.mutedForeground),
      ),
    ),
    UiRow('footer', [
      const UiConfirmDialog(
        'reset',
        'Reset defaults',
        title: 'Reset preferences?',
        message: 'Replace the draft with defaults? Saved preferences stay unchanged until you choose Apply.',
        confirmLabel: 'Reset draft',
        cancelLabel: 'Keep editing',
        style: UiStyle(background: UiColor.token(ThemeToken.secondary)),
      ),
      UiButton(
        'apply',
        dirty ? 'Apply changes' : 'Apply',
        style: UiStyle(background: accentColor),
      ),
    ], style: const UiStyle(justify: UiJustify.spaceBetween)),
  ], style: const UiStyle(gap: 18));

  static const _card = UiStyle(
    padding: [20, 20, 20, 20],
    gap: 14,
    background: UiColor.token(ThemeToken.muted),
    borderRadius: 12,
  );
  UiStyle _navStyle(String target) => UiStyle(
    background: section == target
        ? accentColor
        : const UiColor.token(ThemeToken.secondary),
  );

  Future<void> _restoreName(String name) async {
    final base = await host.readInput('name');
    _nameState = await host.writeInput(
      base,
      text: name,
      selection: UiTextSelection(name.length, name.length),
    );
  }

  Future<void> _handle(GpuiEvent event) async {
    if (event.type == 'input' && event.id == 'name') {
      final state = event.inputState!;
      final last = _nameState;
      // An acknowledged write already incorporates earlier native edits. A
      // delayed event from that edit must not replace the acknowledged value.
      if (last != null &&
          (state.generation < last.generation ||
              (state.generation == last.generation &&
                  state.editRevision < last.editRevision))) {
        return;
      }
      _nameState = state;
      if (draft.name == state.value) {
        return;
      }
      draft = draft.copyWith(name: state.value);
      status = 'Unsaved changes';
    } else if (event.type == 'checkbox_change' && event.id == 'notifications') {
      draft = draft.copyWith(notifications: event.checked);
      status = 'Unsaved changes';
    } else if (event.type == 'slider_change' && event.id == 'spacing') {
      draft = draft.copyWith(spacing: event.number);
      status = 'Unsaved changes';
    } else if (event.type == 'select_change' && event.id == 'accent') {
      draft = draft.copyWith(accent: event.selected);
      status = 'Unsaved changes';
    } else if (event.type == 'click' &&
        const ['general', 'appearance'].contains(event.id)) {
      if (section == event.id) {
        return;
      }
      if (section == 'general') {
        final current = await host.readInput('name');
        if (current.composing) {
          status = 'Finish text composition before switching sections.';
          await host.rebuild();
          return;
        }
        draft = draft.copyWith(name: current.value);
        _nameState = current;
      }
      section = event.id!;
      await host.rebuild();
      if (section == 'general') {
        try {
          await _restoreName(draft.name);
        } on InputWriteException catch (error) {
          if (error.current == null) {
            rethrow;
          }
          _nameState = error.current;
          draft = draft.copyWith(name: error.current!.value);
          status = 'Kept your recent name edit.';
          await host.rebuild();
        }
      }
      return;
    } else if (event.type == 'click' && event.id == 'apply') {
      if (section == 'general') {
        final current = await host.readInput('name');
        if (current.composing) {
          status = 'Finish text composition before applying.';
          await host.rebuild();
          return;
        }
        draft = draft.copyWith(name: current.value);
        _nameState = current;
      }
      if (draft.name.trim().isEmpty) {
        status = 'Enter a display name before applying.';
      } else {
        saved = draft;
        status = 'Preferences applied for this session.';
      }
    } else if (event.type == 'dialog_result' && event.id == 'reset') {
      if (!event.confirmed!) {
        status = 'Reset cancelled. Your draft is unchanged.';
      } else {
        try {
          if (section == 'general') {
            await _restoreName(const Preferences().name);
          }
          draft = const Preferences();
          status = 'Defaults restored. Apply to save them.';
        } on InputWriteException {
          status =
              'The name changed during reset. Finish editing and try again.';
        }
      }
    } else {
      return;
    }
    await host.rebuild();
  }

  Map<String, Object?> describe() => {
    'section': section,
    'draft': draft.toJson(),
    'saved': saved.toJson(),
    'dirty': dirty,
    'status': status,
    'events': Map.of(eventCounts),
    'failure': failure?.toString(),
  };

  Future<void> close() async {
    _closing = true;
    await _pending;
    try {
      await host.close();
    } finally {
      await _subscription.cancel();
    }
  }
}
