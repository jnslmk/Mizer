import 'package:mizer/api/contracts/programmer.dart';
import 'package:mizer/api/plugin/ffi/layout.dart';
import 'package:mizer/views/layout/shared_ticker.dart';
import 'package:test/test.dart';

class _FakeLayoutSource implements LayoutValuesSource {
  @override
  List<LayoutReadValue> readLayoutValues(List<int> kinds, List<String> paths) =>
      List.generate(
        paths.length,
        (_) => LayoutReadValue(
          value: 0,
          min: 0,
          max: 0,
          percentage: false,
          hasColor: false,
          red: 0,
          green: 0,
          blue: 0,
          label: '',
          steps: [],
          beat: 0,
        ),
      );
}

class _FakeProgrammerPointer implements IProgrammerStatePointer {
  int reads = 0;
  ProgrammerState state = ProgrammerState();
  bool disposed = false;

  @override
  ProgrammerState readState() {
    reads++;
    return state;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

LayoutPolling _pollingWith(_FakeProgrammerPointer pointer) {
  final polling = LayoutPolling(_FakeLayoutSource());
  polling.programmerSource = pointer;
  return polling;
}

void main() {
  test('programmer state compares by value for change detection', () {
    expect(ProgrammerState(activeGroups: [1]),
        equals(ProgrammerState(activeGroups: [1])));
    expect(ProgrammerState(activeGroups: [1]),
        isNot(equals(ProgrammerState(activeGroups: [2]))));
  });

  test('one programmer read per tick is shared by all subscribers', () {
    final pointer = _FakeProgrammerPointer()
      ..state = ProgrammerState(activeGroups: [3]);
    final polling = _pollingWith(pointer);
    final first = polling.subscribeProgrammer();
    final second = polling.subscribeProgrammer();
    expect(identical(first, second), isTrue);

    polling.tick(const Duration(seconds: 1));

    expect(pointer.reads, 1);
    expect(first.value.activeGroups, [3]);
    expect(second.value.activeGroups, [3]);
  });

  test('programmer notifier only fires on actual change', () {
    final pointer = _FakeProgrammerPointer();
    final polling = _pollingWith(pointer);
    final notifier = polling.subscribeProgrammer();
    var fires = 0;
    notifier.addListener(() => fires++);

    // Identical default state: the read happens, nobody is notified.
    polling.tick(const Duration(seconds: 1));
    expect(pointer.reads, 1);
    expect(fires, 0);

    // Same state on the next cadence tick: still silent.
    polling.tick(const Duration(seconds: 2));
    expect(pointer.reads, 2);
    expect(fires, 0);

    pointer.state = ProgrammerState(activeGroups: [7]);
    polling.tick(const Duration(seconds: 3));
    expect(fires, 1);
    expect(notifier.value.activeGroups, [7]);
  });

  test('programmer reads follow the shared 30fps cadence', () {
    final pointer = _FakeProgrammerPointer();
    final polling = _pollingWith(pointer);
    polling.subscribeProgrammer();

    polling.tick(Duration.zero);
    polling.tick(const Duration(milliseconds: 32));
    polling.tick(const Duration(milliseconds: 34));

    expect(pointer.reads, 2);
  });

  test('tick without subscribers performs no programmer read', () {
    final pointer = _FakeProgrammerPointer();
    final idle = _pollingWith(pointer);
    idle.tick(const Duration(seconds: 1));
    expect(pointer.reads, 0);
  });

  test('tick with subscribers but no source stays silent', () {
    final polling = LayoutPolling(_FakeLayoutSource());
    final notifier = polling.subscribeProgrammer();
    var fires = 0;
    notifier.addListener(() => fires++);
    polling.tick(const Duration(seconds: 1));
    expect(fires, 0);
    expect(notifier.value, equals(ProgrammerState()));
  });

  test('last programmer unsubscribe disposes the shared notifier', () {
    final pointer = _FakeProgrammerPointer();
    final polling = _pollingWith(pointer);
    final first = polling.subscribeProgrammer();
    polling.subscribeProgrammer();

    polling.unsubscribeProgrammer();
    polling.tick(const Duration(seconds: 1));
    expect(pointer.reads, 1);

    polling.unsubscribeProgrammer();
    polling.tick(const Duration(seconds: 2));
    expect(pointer.reads, 1);

    final fresh = polling.subscribeProgrammer();
    expect(identical(fresh, first), isFalse);
  });

  test('programmer subscriber delivers the current value then tracks change',
      () {
    final pointer = _FakeProgrammerPointer()
      ..state = ProgrammerState(activeGroups: [1]);
    final polling = _pollingWith(pointer);
    var seen = <int>[];
    late final ProgrammerSubscriber subscriber;
    subscriber = ProgrammerSubscriber(
      polling,
      () => seen = List.of(subscriber.notifier!.value.activeGroups),
    );
    subscriber.attach();
    // Pre-poll default, like LayoutSubscriber before the first tick.
    expect(seen, isEmpty);

    polling.tick(const Duration(seconds: 1));
    expect(seen, [1]);

    polling.tick(const Duration(seconds: 2));
    expect(seen, [1]);

    pointer.state = ProgrammerState(activeGroups: [1, 2]);
    polling.tick(const Duration(seconds: 3));
    expect(seen, [1, 2]);

    subscriber.dispose();
    polling.tick(const Duration(seconds: 4));
    // Detached: no more reads once the last subscriber leaves.
    expect(pointer.reads, 3);
  });
}
