import 'style.dart';

enum UiThemeMode { light, dark }

/// A built-in palette with opaque overrides for the SDK's existing color tokens.
/// Every snapshot replaces the full descriptor. Missing overrides reset to the
/// built-in palette; an omitted theme selects light.
final class UiTheme {
  const UiTheme({this.mode = UiThemeMode.light, this.overrides = const {}});
  const UiTheme.light({this.overrides = const {}}) : mode = UiThemeMode.light;
  const UiTheme.dark({this.overrides = const {}}) : mode = UiThemeMode.dark;

  final UiThemeMode mode;
  final Map<ThemeToken, String> overrides;

  Map<String, Object> toJson() {
    if (overrides.length > 16) {
      throw ArgumentError('A theme supports at most 16 token overrides');
    }
    final colors = <String, String>{};
    for (final entry in overrides.entries) {
      if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(entry.value)) {
        throw ArgumentError('Theme colors must be opaque #RRGGBB values');
      }
      colors[entry.key.wire] = entry.value.toUpperCase();
    }
    return {'mode': mode.name, if (colors.isNotEmpty) 'overrides': colors};
  }
}
