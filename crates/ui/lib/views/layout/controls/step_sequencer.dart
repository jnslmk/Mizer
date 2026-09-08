import 'package:collection/collection.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:mizer/api/contracts/nodes.dart';
import 'package:mizer/consts.dart';
import 'package:mizer/protos/layouts.pb.dart' hide Color;
import 'package:mizer/protos/nodes.pb.dart';
import 'package:mizer/views/layout/shared_ticker.dart';
import 'package:mizer/widgets/inputs/button.dart';
import 'package:provider/provider.dart';

class StepSequencerControl extends StatefulWidget {
  final LayoutControl control;
  final Color? color;
  final ControlSize? size;

  const StepSequencerControl({
    required this.control,
    required this.color,
    this.size,
    Key? key,
  }) : super(key: key);

  @override
  _StepSequencerControlState createState() => _StepSequencerControlState();
}

class _StepSequencerControlState extends State<StepSequencerControl> {
  List<bool> value = List.filled(16, false);
  int beat = 0;
  LayoutSubscriber? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscription ??= LayoutSubscriber(
      LayoutPollingScope.of(context),
      LayoutValueKind.stepSequencer,
      _onValue,
    );
    _subscription!.resubscribe(widget.control.node.path);
  }

  @override
  void didUpdateWidget(StepSequencerControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _subscription?.resubscribe(widget.control.node.path);
  }

  void _onValue() {
    final next = _subscription!.notifier!.value;
    if ((!const ListEquality<bool>().equals(value, next.steps) ||
            beat != next.beat) &&
        mounted) {
      setState(() {
        value = next.steps;
        beat = next.beat;
      });
    }
  }

  @override
  void dispose() {
    _subscription?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    NodesApi apiClient = context.read();
    return Row(
      children: value.mapIndexed((i, v) {
        var controlColor = widget.color ?? Grey700;
        if (i % 4 == 0) {
          controlColor =
              controlColor.withRed((controlColor.red8bit + 10).clamp(0, 255));
          controlColor = controlColor
              .withGreen((controlColor.green8bit + 10).clamp(0, 255));
          controlColor =
              controlColor.withBlue((controlColor.blue8bit + 10).clamp(0, 255));
        }
        if (i == beat) {
          controlColor =
              controlColor.withRed((controlColor.red8bit - 20).clamp(0, 255));
          controlColor = controlColor
              .withGreen((controlColor.green8bit - 20).clamp(0, 255));
          controlColor =
              controlColor.withBlue((controlColor.blue8bit - 20).clamp(0, 255));
        }
        return ButtonInput(
          label: (i + 1).toString(),
          color: controlColor,
          pressed: v,
          width: 1,
          height: 1,
          onValue: (v) {
            if (v == 0) {
              return;
            }
            final newValue = List<bool>.from(value);
            newValue[i] = !newValue[i];
            apiClient.updateNodeSetting(
              UpdateNodeSettingRequest(
                path: widget.control.node.path,
                setting: NodeSetting(
                  id: "Steps",
                  stepSequencerValue:
                      NodeSetting_StepSequencerValue(steps: newValue),
                ),
              ),
            );
          },
        );
      }).toList(),
      spacing: GRID_GAP_SIZE,
    );
  }
}
