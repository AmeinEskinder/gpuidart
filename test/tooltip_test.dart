import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test('tooltip is bounded help, separate from button name', () {
    const button = UiButton(
      'refresh',
      'Refresh',
      tooltip: 'Update sample prices',
    );
    expect(button.toJson()['tooltip'], 'Update sample prices');
    expect(button.toJson()['label'], 'Refresh');
    expect(
      const UiButton('plain', 'Plain').toJson().containsKey('tooltip'),
      false,
    );
    expect(
      UiButton('b', 'B', tooltip: 'é' * 512).toJson()['tooltip'],
      isNotNull,
    );
    for (final help in ['', 'é' * 513]) {
      expect(
        () => UiButton('b', 'B', tooltip: help).toJson(),
        throwsArgumentError,
      );
    }
  });
}
