import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mizer/api/contracts/programmer.dart';
import 'package:mizer/protos/layouts.pb.dart' show ControlSize;
import 'package:mizer/state/presets_bloc.dart';
import 'package:mizer/views/layout/shared_ticker.dart';
import 'package:mizer/widgets/grid/grid_tile.dart';
import 'package:mizer/widgets/high_contrast_text.dart';

class GroupControl extends StatefulWidget {
  final String? label;
  final Color? color;
  final int groupId;
  final ControlSize size;

  const GroupControl(
      {required this.label, this.color, required this.groupId, required this.size, Key? key})
      : super(key: key);

  @override
  State<GroupControl> createState() => _GroupControlState();
}

class _GroupControlState extends State<GroupControl> {
  bool _active = false;
  ProgrammerSubscriber? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscription ??= ProgrammerSubscriber(
      LayoutPollingScope.of(context),
      _onValue,
    );
    _subscription!.attach();
  }

  @override
  void didUpdateWidget(GroupControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keyless reuse (control.dart) can retarget this State at another groupId;
    // re-project against the latest shared value. _onValue no-ops unless the
    // bool flips, same convention as the #2 controls.
    _onValue();
  }
  void _onValue() {
    final next =
        _subscription!.notifier!.value.activeGroups.contains(_groupId);
    if (next != _active && mounted) {
      setState(() => _active = next);
    }
  }

  @override
  void dispose() {
    _subscription?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PresetsBloc, PresetsState>(builder: (context, state) {
      return PanelGridTile(
        color: widget.color,
        onTap: () => _callGroup(),
          active: _active,
          child: Center(
              child: HighContrastText(_getLabel(state), textAlign: TextAlign.center)
      ));
    });
  }

  int get _groupId {
    return widget.groupId;
  }

  _callGroup() {
    var programmerApi = context.read<ProgrammerApi>();
    programmerApi.selectGroup(_groupId);
  }

  String _getLabel(PresetsState state) {
    if (widget.label != null && widget.label!.isNotEmpty) {
      return widget.label!;
    }

    return state.groups.firstWhere((g) => g.id == _groupId).name;
  }
}
