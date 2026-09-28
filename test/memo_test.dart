import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test('a memo keeps its value while the inputs are equal', () {
    final memo = UiMemo<UiNode>();
    var builds = 0;
    UiNode build(String title) => memo.of([title, 3], () {
      builds++;
      return UiText('title', title);
    });
    final first = build('A');
    expect(identical(build('A'), first), isTrue);
    expect(builds, 1);
    final second = build('B');
    expect(identical(second, first), isFalse);
    expect(builds, 2);
    expect(identical(build('B'), second), isTrue);
    memo.reset();
    expect(identical(build('B'), second), isFalse);
    expect(builds, 3);
  });

  test('memo inputs compare by value and by length', () {
    final memo = UiMemo<String>();
    expect(memo.of([1, 'a'], () => 'first'), 'first');
    expect(memo.of([1, 'a'], () => 'second'), 'first');
    expect(memo.of([1, 'a', null], () => 'third'), 'third');
    expect(memo.of([1, 'a'], () => 'fourth'), 'fourth');
  });
}
