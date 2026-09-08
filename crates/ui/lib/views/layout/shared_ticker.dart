import 'package:collection/collection.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:mizer/api/contracts/programmer.dart';
import 'package:mizer/api/plugin/ffi/layout.dart';
import 'package:provider/provider.dart';

const _pollInterval = Duration(milliseconds: 33);

bool shouldPoll(Duration? previous, Duration elapsed) =>
    previous == null || elapsed - previous >= _pollInterval;

// The declaration order here is the batch protocol: LayoutPolling sends
// kind.index over FFI and the Rust match arms in layout.rs read 0..5 in this
// exact order. Reorder both sides together, never just this enum.
enum LayoutValueKind { fader, dial, button, label, stepSequencer, level }

class LayoutControlValue {
  final double value;
  final double min;
  final double max;
  final bool percentage;
  final bool hasColor;
  final double red;
  final double green;
  final double blue;
  final String label;
  final List<bool> steps;
  final int beat;

  const LayoutControlValue({
    this.value = 0,
    this.min = 0,
    this.max = 0,
    this.percentage = false,
    this.hasColor = false,
    this.red = 0,
    this.green = 0,
    this.blue = 0,
    this.label = '',
    this.steps = const [],
    this.beat = 0,
  });

  const LayoutControlValue.number(double value) : this(value: value);
  const LayoutControlValue.steps(List<bool> steps, int beat)
      : this(steps: steps, beat: beat);

  factory LayoutControlValue.fromRaw(LayoutReadValue raw) => LayoutControlValue(
        value: raw.value,
        min: raw.min,
        max: raw.max,
        percentage: raw.percentage,
        hasColor: raw.hasColor,
        red: raw.red,
        green: raw.green,
        blue: raw.blue,
        label: raw.label,
        steps: raw.steps,
        beat: raw.beat,
      );

  @override
  bool operator ==(Object other) =>
      other is LayoutControlValue &&
      value == other.value &&
      min == other.min &&
      max == other.max &&
      percentage == other.percentage &&
      hasColor == other.hasColor &&
      red == other.red &&
      green == other.green &&
      blue == other.blue &&
      label == other.label &&
      const ListEquality<bool>().equals(steps, other.steps) &&
      beat == other.beat;

  @override
  int get hashCode => Object.hash(value, min, max, percentage, hasColor, red,
      green, blue, label, const ListEquality<bool>().hash(steps), beat);
}

class LayoutPollingScope extends StatefulWidget {
  final LayoutValuesSource source;
  final Widget child;

  const LayoutPollingScope(
      {required this.source, required this.child, super.key});

  // Kept for existing callers that pass the FFI pointer directly.
  factory LayoutPollingScope.pointer(
          {required LayoutsRefPointer pointer, required Widget child}) =>
      LayoutPollingScope(source: pointer, child: child);

  static LayoutPolling of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_LayoutPollingInherited>()!
      .polling;

  @override
  State<LayoutPollingScope> createState() => _LayoutPollingScopeState();
}

class _LayoutPollingScopeState extends State<LayoutPollingScope>
    with SingleTickerProviderStateMixin {
  late LayoutPolling _polling = LayoutPolling(widget.source);
  late Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_polling.tick)..start();
    // One programmer pointer per layout view, shared by all group
    // subscribers through LayoutPolling (same pattern as SequencerStateFetcher).
    context.read<ProgrammerApi>().getProgrammerPointer().then((pointer) {
      if (!mounted) {
        pointer?.dispose();
        return;
      }
      _polling.programmerSource = pointer;
    });
  }

  @override
  void didUpdateWidget(LayoutPollingScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _polling.source = widget.source;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _polling.programmerSource?.dispose();
    _polling.programmerSource = null;
    _polling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LayoutPollingInherited(polling: _polling, child: widget.child);
}

class _LayoutPollingInherited extends InheritedWidget {
  final LayoutPolling polling;

  const _LayoutPollingInherited({required this.polling, required super.child});

  @override
  bool updateShouldNotify(_LayoutPollingInherited oldWidget) => false;
}

class _SharedEntry {
  final ValueNotifier<LayoutControlValue> notifier =
      ValueNotifier(const LayoutControlValue());
  int refs = 0;
}

class LayoutPolling {
  LayoutValuesSource source;
  IProgrammerStatePointer? programmerSource;
  final Map<_LayoutRequest, _SharedEntry> _entries = {};
  final ValueNotifier<int> _tickListeners = ValueNotifier(0);
  ValueNotifier<ProgrammerState>? _programmerNotifier;
  int _programmerRefs = 0;
  Duration? _lastPoll;

  LayoutPolling(this.source);

  void addTickListener(VoidCallback listener) =>
      _tickListeners.addListener(listener);

  void dispose() {
    _tickListeners.dispose();
    _programmerNotifier?.dispose();
    _programmerNotifier = null;
  }

  /// Shared programmer-state subscription: one FFI read per tick no matter
  /// how many group controls listen; the notifier only fires on exact change.
  ValueNotifier<ProgrammerState> subscribeProgrammer() {
    _programmerRefs++;
    return _programmerNotifier ??= ValueNotifier(ProgrammerState());
  }

  void unsubscribeProgrammer() {
    if (_programmerRefs <= 0) return;
    _programmerRefs--;
    if (_programmerRefs <= 0) {
      _programmerRefs = 0;
      _programmerNotifier?.dispose();
      _programmerNotifier = null;
    }
  }
  void removeTickListener(VoidCallback listener) =>
      _tickListeners.removeListener(listener);

  ValueNotifier<LayoutControlValue> subscribe(
      String path, LayoutValueKind kind) {
    final entry =
        _entries.putIfAbsent(_LayoutRequest(path, kind), () => _SharedEntry());
    entry.refs++;
    return entry.notifier;
  }

  void unsubscribe(String path, LayoutValueKind kind) {
    final key = _LayoutRequest(path, kind);
    final entry = _entries[key];
    if (entry == null) return;
    entry.refs--;
    if (entry.refs <= 0) {
      _entries.remove(key);
      entry.notifier.dispose();
    }
  }

  void tick(Duration elapsed) {
    if (!shouldPoll(_lastPoll, elapsed)) return;
    _lastPoll = elapsed;
    if (_entries.isNotEmpty) {
      final requests = _entries.keys.toList(growable: false);
      final values = source.readLayoutValues(
          requests.map((request) => request.kind.index).toList(),
          requests.map((request) => request.path).toList());
      for (var index = 0; index < requests.length; index++) {
        final entry = _entries[requests[index]];
        if (entry == null) continue;
        final value = LayoutControlValue.fromRaw(values[index]);
        if (entry.notifier.value != value) entry.notifier.value = value;
      }
    }
    final programmerNotifier = _programmerNotifier;
    final programmerSource = this.programmerSource;
    if (programmerNotifier != null && programmerSource != null) {
      final next = programmerSource.readState();
      if (programmerNotifier.value != next) programmerNotifier.value = next;
    }
    _tickListeners.value++;
  }
}

/// Per-widget subscription handle shared by all layout controls.
///
/// Tracks the subscribed path so a State reused for a different node path
/// (keyless element reuse on delete/reorder) resubscribes instead of polling
/// the stale path, and balances subscribe/unsubscribe calls so shared
/// notifiers survive until their last subscriber leaves.
class LayoutSubscriber {
  final LayoutPolling _polling;
  final LayoutValueKind _kind;
  final VoidCallback _onValue;
  String? _path;
  ValueNotifier<LayoutControlValue>? _notifier;

  LayoutSubscriber(this._polling, this._kind, this._onValue);

  ValueNotifier<LayoutControlValue>? get notifier => _notifier;

  void resubscribe(String path) {
    if (_path == path && _notifier != null) return;
    if (_path != null) {
      _notifier?.removeListener(_onValue);
      _polling.unsubscribe(_path!, _kind);
      _notifier = null;
    }
    _notifier = _polling.subscribe(path, _kind)..addListener(_onValue);
    _path = path;
    _onValue();
  }

  void dispose() {
    if (_path != null) {
      _notifier?.removeListener(_onValue);
      _polling.unsubscribe(_path!, _kind);
      _path = null;
      _notifier = null;
    }
  }
}

/// Per-widget handle on the shared programmer-state notifier.
///
/// Group controls attach once and project the `activeGroups` membership they
/// display; attach/dispose balance subscribe/unsubscribe calls so the shared
/// notifier (and its once-per-tick FFI read) lives only while subscribers
/// remain. Mirrors [LayoutSubscriber] without a node path: every subscriber
/// shares the same whole-state read.
class ProgrammerSubscriber {
  final LayoutPolling _polling;
  final VoidCallback _onValue;
  ValueNotifier<ProgrammerState>? _notifier;

  ProgrammerSubscriber(this._polling, this._onValue);

  ValueNotifier<ProgrammerState>? get notifier => _notifier;

  void attach() {
    if (_notifier != null) return;
    _notifier = _polling.subscribeProgrammer()..addListener(_onValue);
    _onValue();
  }

  void dispose() {
    if (_notifier == null) return;
    _notifier!.removeListener(_onValue);
    _polling.unsubscribeProgrammer();
    _notifier = null;
  }
}

class _LayoutRequest {
  final String path;
  final LayoutValueKind kind;

  const _LayoutRequest(this.path, this.kind);

  @override
  bool operator ==(Object other) =>
      other is _LayoutRequest && path == other.path && kind == other.kind;

  @override
  int get hashCode => Object.hash(path, kind);
}
