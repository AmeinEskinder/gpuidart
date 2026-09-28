import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test('theme encodes built-in modes and the existing token vocabulary', () {
    expect(const UiTheme.light().toJson(), {'mode': 'light'});
    expect(const UiTheme.dark().toJson(), {'mode': 'dark'});
    final theme = UiTheme(
      mode: UiThemeMode.dark,
      overrides: {for (final token in ThemeToken.values) token: '#abcdef'},
    );
    expect(theme.toJson()['overrides'], {
      for (final token in ThemeToken.values) token.wire: '#ABCDEF',
    });
  });

  test('theme rejects references, alpha, malformed and injected colors', () {
    for (final value in [
      'token:foreground',
      '#ABC',
      '#12345600',
      '#GGGGGG',
      '#123456\n',
      'url(theme.json)',
      '#日00',
    ]) {
      expect(
        () => UiTheme(overrides: {ThemeToken.primary: value}).toJson(),
        throwsArgumentError,
        reason: value,
      );
    }
  });
}
