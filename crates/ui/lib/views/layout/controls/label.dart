import 'package:flutter/material.dart';
import 'package:mizer/protos/layouts.pb.dart' hide Color;
import 'package:mizer/views/layout/shared_ticker.dart';
import 'package:mizer/widgets/grid/grid_tile.dart';
import 'package:mizer/widgets/high_contrast_text.dart';

class LabelControl extends StatefulWidget {
  final LayoutControl control;
  final Color? color;

  const LabelControl({
    required this.control,
    required this.color,
    Key? key,
  }) : super(key: key);

  @override
  _LabelControlState createState() => _LabelControlState();
}

class _LabelControlState extends State<LabelControl> {
  String value = "";
  LayoutSubscriber? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscription ??= LayoutSubscriber(
      LayoutPollingScope.of(context),
      LayoutValueKind.label,
      _onValue,
    );
    _subscription!.resubscribe(widget.control.node.path);
  }

  @override
  void didUpdateWidget(LabelControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _subscription?.resubscribe(widget.control.node.path);
  }

  void _onValue() {
    final next = _subscription!.notifier!.value.label;
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
    return PanelGridTile(
      interactive: false,
      color: widget.color,
      child: Center(
        child: HighContrastText(
          value,
          textAlign: TextAlign.center,
          autoSize: AutoSize(minFontSize: 10, wrapWords: false),
        ),
      ),
    );
  }
}
