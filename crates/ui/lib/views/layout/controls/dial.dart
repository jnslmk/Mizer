import 'package:flutter/widgets.dart';
import 'package:mizer/api/contracts/nodes.dart';
import 'package:mizer/api/plugin/ffi/layout.dart';
import 'package:mizer/protos/layouts.pb.dart' hide Color;
import 'package:mizer/views/layout/shared_ticker.dart';
import 'package:mizer/widgets/inputs/encoder.dart';
import 'package:provider/provider.dart';

class DialControl extends StatefulWidget {
  final LayoutsRefPointer pointer;
  final LayoutControl control;
  final Color? color;

  const DialControl({
    required this.pointer,
    required this.control,
    required this.color,
    Key? key,
  }) : super(key: key);

  @override
  _DialControlState createState() => _DialControlState();
}

class _DialControlState extends State<DialControl> {
  double value = 0;
  double min = 0;
  double max = 1;
  bool isPercentage = true;
  LayoutSubscriber? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscription ??= LayoutSubscriber(
      LayoutPollingScope.of(context),
      LayoutValueKind.dial,
      _onValue,
    );
    _subscription!.resubscribe(widget.control.node.path);
  }

  @override
  void didUpdateWidget(DialControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _subscription?.resubscribe(widget.control.node.path);
  }

  void _onValue() {
    final next = _subscription!.notifier!.value;
    if ((value != next.value ||
            min != next.min ||
            max != next.max ||
            isPercentage != next.percentage) &&
        mounted) {
      setState(() {
        value = next.value;
        min = next.min;
        max = next.max;
        isPercentage = next.percentage;
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
    return EncoderInput(
      labelInDial:
          widget.control.size.width == 1 && widget.control.size.height == 1,
      label: widget.control.label,
      color: widget.color,
      value: value,
      maxValue: max,
      percentage: isPercentage,
      onValue: (value) => apiClient.writeControlValue(
        path: widget.control.node.path,
        port: "Input",
        value: value,
      ),
    );
  }
}
