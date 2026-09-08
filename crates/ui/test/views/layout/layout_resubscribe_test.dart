import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mizer/api/plugin/ffi/layout.dart';
import 'package:mizer/views/layout/shared_ticker.dart';

class _FakeSource implements LayoutValuesSource {
  List<String> lastPaths = const [];
  int calls = 0;

  @override
  List<LayoutReadValue> readLayoutValues(List<int> kinds, List<String> paths) {
    calls++;
    lastPaths = List.of(paths);
    return List.generate(
      paths.length,
      (_) => const LayoutReadValue(
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
}

class _Probe extends StatefulWidget {
  final String path;

  const _Probe({required this.path});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  LayoutSubscriber? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= LayoutSubscriber(
        LayoutPollingScope.of(context), LayoutValueKind.fader, () {});
    _sub!.resubscribe(widget.path);
  }

  @override
  void didUpdateWidget(_Probe oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sub?.resubscribe(widget.path);
  }

  @override
  void dispose() {
    _sub?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  test('shared notifier survives one of two subscribers leaving', () {
    final source = _FakeSource();
    final polling = LayoutPolling(source);
    final first = polling.subscribe('fader', LayoutValueKind.fader);
    final second = polling.subscribe('fader', LayoutValueKind.fader);
    expect(identical(first, second), isTrue);

    polling.unsubscribe('fader', LayoutValueKind.fader);
    polling.tick(const Duration(seconds: 1));

    expect(source.calls, 1);
    expect(source.lastPaths, ['fader']);

    polling.unsubscribe('fader', LayoutValueKind.fader);
    polling.tick(const Duration(seconds: 2));

    expect(source.calls, 1);
  });

  testWidgets('rebinding a state to a new path polls the new path',
      (tester) async {
    final source = _FakeSource();
    await tester.pumpWidget(LayoutPollingScope(
      source: source,
      child: const Directionality(
          textDirection: TextDirection.ltr, child: _Probe(path: 'old')),
    ));
    LayoutPollingScope.of(tester.element(find.byType(_Probe)))
        .tick(const Duration(seconds: 1));
    expect(source.lastPaths, ['old']);

    await tester.pumpWidget(LayoutPollingScope(
      source: source,
      child: const Directionality(
          textDirection: TextDirection.ltr, child: _Probe(path: 'new')),
    ));
    LayoutPollingScope.of(tester.element(find.byType(_Probe)))
        .tick(const Duration(seconds: 2));
    expect(source.lastPaths, ['new']);
  });
}
