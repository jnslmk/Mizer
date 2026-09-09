import 'package:flutter/widgets.dart';
import 'package:mizer/api/contracts/nodes.dart';
import 'package:mizer/api/plugin/ffi/layout.dart';
import 'package:mizer/protos/layouts.pb.dart' hide Color;
import 'package:mizer/views/layout/shared_ticker.dart';
import 'package:mizer/widgets/inputs/button.dart';
import 'package:provider/provider.dart';

class ButtonControl extends StatefulWidget {
  final LayoutsRefPointer pointer;
  final LayoutControl control;
  final Color? color;
  final MemoryImage? image;
  final ControlSize? size;

  const ButtonControl({
    required this.pointer,
    required this.control,
    required this.color,
    required this.image,
    this.size,
    Key? key,
  }) : super(key: key);

  @override
  _ButtonControlState createState() => _ButtonControlState();
}

class _ButtonControlState extends State<ButtonControl> {
  bool value = false;
  Color? color;
  LayoutSubscriber? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscription ??= LayoutSubscriber(
      LayoutPollingScope.of(context),
      LayoutValueKind.button,
      _onValue,
    );
    _subscription!.resubscribe(widget.control.node.path);
  }

  @override
  void didUpdateWidget(ButtonControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _subscription?.resubscribe(widget.control.node.path);
  }

  void _onValue() {
    final next = _subscription!.notifier!.value;
    final nextColor = next.hasColor
        ? Color.fromARGB(
            255,
            (next.red * 255).toInt(),
            (next.green * 255).toInt(),
            (next.blue * 255).toInt(),
          )
        : null;
    if ((value != (next.value != 0) || color != nextColor) && mounted) {
      setState(() {
        value = next.value != 0;
        color = nextColor;
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
    return ButtonInput(
      hotkey: widget.control.hasHotkey() ? widget.control.hotkey : null,
      label: widget.control.label,
      color: color ?? widget.color,
      image: widget.image,
      pressed: value,
      width: widget.size?.width.toInt(),
      height: widget.size?.height.toInt(),
      onValue: (value) => apiClient.writeControlValue(
        path: widget.control.node.path,
        port: "Input",
        value: value,
      ),
    );
  }
}
