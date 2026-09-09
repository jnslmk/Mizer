import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mizer/api/contracts/programmer.dart';
import 'package:mizer/api/plugin/ffi/layout.dart';
import 'package:mizer/protos/layouts.pb.dart' show ControlSize;
import 'package:mizer/state/presets_bloc.dart';
import 'package:mizer/views/layout/controls/group.dart';
import 'package:mizer/views/layout/shared_ticker.dart';
import 'package:mizer/widgets/grid/grid_tile.dart';
import 'package:provider/provider.dart';

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
  ProgrammerState state = ProgrammerState();

  @override
  ProgrammerState readState() => state;

  @override
  void dispose() {}
}

class _StubProgrammerApi implements ProgrammerApi {
  @override
  Future<IProgrammerStatePointer?> getProgrammerPointer() =>
      Future.value(null);

  @override
  Future<Groups> getGroups() => Future.value(Groups());

  @override
  Future<Presets> getPresets() => Future.value(Presets());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'retargeting groupId re-projects highlight without a notifier tick',
      (tester) async {
    final layoutSource = _FakeLayoutSource();
    final pointer = _FakeProgrammerPointer()
      ..state = ProgrammerState(activeGroups: [1]);
    final presetsBloc = PresetsBloc(_StubProgrammerApi());

    Widget app(int groupId) => MaterialApp(
          home: Provider<ProgrammerApi>.value(
            value: _StubProgrammerApi(),
            child: BlocProvider<PresetsBloc>.value(
              value: presetsBloc,
              child: LayoutPollingScope(
                source: layoutSource,
                child: GroupControl(
                  label: 'tile',
                  groupId: groupId,
                  size: ControlSize(),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(app(1));
    final polling =
        LayoutPollingScope.of(tester.element(find.byType(GroupControl)));
    polling.programmerSource = pointer;
    polling.tick(const Duration(seconds: 1));
    await tester.pump();
    expect(
      tester.widget<PanelGridTile>(find.byType(PanelGridTile)).active,
      isTrue,
    );

    // Same State, new groupId (keyless reuse, as in control.dart): the
    // highlight must follow B with no engine-side change and no tick.
    await tester.pumpWidget(app(2));
    await tester.pump();
    expect(
      tester.widget<PanelGridTile>(find.byType(PanelGridTile)).active,
      isFalse,
    );

    presetsBloc.close();
  });
}
