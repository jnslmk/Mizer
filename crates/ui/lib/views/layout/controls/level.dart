import 'package:flutter/widgets.dart';
import 'package:mizer/api/plugin/ffi/layout.dart';
import 'package:mizer/protos/layouts.pb.dart' hide Color;
import 'package:mizer/views/layout/shared_ticker.dart';
import 'package:mizer/widgets/inputs/level.dart';

class LevelControl extends StatefulWidget {
  final LayoutsRefPointer pointer;
  final LayoutControl control;
  final Color? color;

  const LevelControl({
    required this.pointer,
    required this.control,
    required this.color,
    Key? key,
  }) : super(key: key);

  @override
  _LevelControlState createState() => _LevelControlState();
}

class _LevelControlState extends State<LevelControl> {
  double value = 0;
  LayoutSubscriber? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscription ??= LayoutSubscriber(
      LayoutPollingScope.of(context),
      LayoutValueKind.level,
      _onValue,
    );
    _subscription!.resubscribe(widget.control.node.path);
  }

  @override
  void didUpdateWidget(LevelControl oldWidget) {
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
    return LevelDisplay(color: widget.color, value: value);
  }
}
