import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mizer/api/contracts/programmer.dart';
import 'package:mizer/protos/layouts.pb.dart' show ControlSize;
import 'package:mizer/state/presets_bloc.dart';
import 'package:mizer/widgets/grid/grid_tile.dart';
import 'package:mizer/widgets/high_contrast_text.dart';

/// Static preset tile: it displays no programmer state, so unlike
/// [GroupControl] it needs no polling subscription at all and rebuilds only
/// when [PresetsBloc] emits or its parent rebuilds.
class PresetControl extends StatelessWidget {
  final String? label;
  final Color? color;
  final PresetId presetId;
  final ControlSize size;

  const PresetControl(
      {required this.label, this.color, required this.presetId, required this.size, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PresetsBloc, PresetsState>(builder: (context, state) {
      return PanelGridTile(
        color: color,
        onTap: () => _callPreset(context),
        child: Center(
            child: HighContrastText(_getLabel(state), textAlign: TextAlign.center))
      );
    });
  }

  PresetId get _presetId {
    return presetId;
  }

  _callPreset(BuildContext context) {
    var programmerApi = context.read<ProgrammerApi>();
    programmerApi.callPreset(_presetId);
  }

  String _getLabel(PresetsState state) {
    if (label != null && label!.isNotEmpty) {
      return label!;
    }

    return _getPresets(state).firstWhereOrNull((p) => p.id == _presetId)?.label ?? "";
  }

  List<Preset> _getPresets(PresetsState state) {
    var presets = state.presets.intensities.toList();
    presets.addAll(state.presets.colors);
    presets.addAll(state.presets.shutters);
    presets.addAll(state.presets.positions);

    return presets;
  }
}
