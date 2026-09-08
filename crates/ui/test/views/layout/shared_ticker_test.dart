import 'package:mizer/views/layout/shared_ticker.dart';
import 'package:test/test.dart';

void main() {
  test('polling is capped at 30fps', () {
    expect(shouldPoll(null, const Duration()), isTrue);
    expect(shouldPoll(const Duration(), const Duration(milliseconds: 32)),
        isFalse);
    expect(
        shouldPoll(const Duration(), const Duration(milliseconds: 34)), isTrue);
  });

  test('layout values compare exact values including step lists', () {
    expect(
        LayoutControlValue.number(0.5), equals(LayoutControlValue.number(0.5)));
    expect(LayoutControlValue.number(0.5),
        isNot(equals(LayoutControlValue.number(0.5000001))));
    expect(LayoutControlValue.steps(const [true, false], 2),
        equals(LayoutControlValue.steps(const [true, false], 2)));
    expect(LayoutControlValue.steps(const [true, false], 2),
        isNot(equals(LayoutControlValue.steps(const [false, true], 2))));
  });
}
