import 'package:flutter/widgets.dart';
import 'package:mizer/api/contracts/nodes.dart';
import 'package:mizer/protos/layouts.pb.dart' hide Color;
import 'package:mizer/views/layout/shared_ticker.dart';
import 'package:mizer/widgets/inputs/fader.dart';
import 'package:provider/provider.dart';

class FaderControl extends StatefulWidget {
  final LayoutControl control;
  final Color? color;

  const FaderControl({
    required this.control,
    required this.color,
    Key? key,
  }) : super(key: key);

  @override
  _FaderControlState createState() => _FaderControlState();
}

class _FaderControlState extends State<FaderControl> {
  double value = 0;
  LayoutSubscriber? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscription ??= LayoutSubscriber(
      LayoutPollingScope.of(context),
      LayoutValueKind.fader,
      _onValue,
    );
    _subscription!.resubscribe(widget.control.node.path);
  }

  @override
  void didUpdateWidget(FaderControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _subscription?.resubscribe(widget.control.node.path);
  }

  void _onValue() {
    final next = _subscription!.notifier!.value.value;
    if (value != next && mounted) {
      setState(() => value = next);
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
    return FaderInput(
      label: widget.control.label,
      color: widget.color,
      value: value,
      onValue: (value) => apiClient.writeControlValue(
        path: widget.control.node.path,
        port: "Input",
        value: value,
      ),
    );
  }
}
