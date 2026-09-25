import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test('action serializes to the wire shape', () {
    expect(const UiAction(name: 'app.search', keys: 'ctrl+f').toJson(), {
      'name': 'app.search',
      'keys': 'ctrl+f',
      'context': 'global',
    });
    expect(
      const UiAction(
        name: 'watchlist.add',
        keys: 'ctrl+enter',
        context: UiActionContext.node('quotes-table'),
      ).toJson(),
      {
        'name': 'watchlist.add',
        'keys': 'ctrl+enter',
        'context': 'quotes-table',
      },
    );
  });

  test('action validates nonempty name, keys and context ID', () {
    expect(
      () => const UiAction(name: '', keys: 'ctrl+f').toJson(),
      throwsArgumentError,
    );
    expect(
      () => const UiAction(name: 'a', keys: '').toJson(),
      throwsArgumentError,
    );
    expect(
      () => const UiAction(
        name: 'a',
        keys: 'ctrl+f',
        context: UiActionContext.node(''),
      ).toJson(),
      throwsArgumentError,
    );
  });
}
