import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:mizer/api/plugin/ffi/bindings.dart';
import 'package:mizer/api/plugin/ffi/ffi_pointer.dart';
import 'package:mizer/protos/layouts.pb.dart';

import 'api.dart';

class LayoutsRefPointer extends FFIPointer<LayoutRef>
    implements LayoutValuesSource {
  final FFIBindings _bindings;

  LayoutsRefPointer(this._bindings, ffi.Pointer<LayoutRef> ptr) : super(ptr);

  double readFaderValue(String path) {
    return using((arena) {
      var ffiPath = path.toNativeUtf8(allocator: arena);
      var result =
          this._bindings.read_fader_value(ptr, ffiPath.cast<ffi.Char>());

      return result;
    });
  }

  FFIDialValue readDialValue(String path) {
    return using((arena) {
      var ffiPath = path.toNativeUtf8(allocator: arena);
      var result =
          this._bindings.read_dial_value(ptr, ffiPath.cast<ffi.Char>());

      return result;
    });
  }

  bool readButtonValue(String path) {
    return using((arena) {
      var ffiPath = path.toNativeUtf8(allocator: arena);
      var result =
          this._bindings.read_button_value(ptr, ffiPath.cast<ffi.Char>());

      return result == 1;
    });
  }

  String readLabelValue(String path) {
    return using((arena) {
      var ffiPath = path.toNativeUtf8(allocator: arena);
      var result =
          this._bindings.read_label_value(ptr, ffiPath.cast<ffi.Char>());

      return result.cast<Utf8>().toDartString();
    });
  }

  Timecode readClockValue(String path) {
    return using((arena) {
      var ffiPath = path.toNativeUtf8(allocator: arena);
      var result =
          this._bindings.read_clock_value(ptr, ffiPath.cast<ffi.Char>());

      return result;
    });
  }

  Color? readControlColor(String path) {
    return using((arena) {
      var ffiPath = path.toNativeUtf8(allocator: arena);
      var result =
          this._bindings.read_control_color(ptr, ffiPath.cast<ffi.Char>());

      if (result.has_color == 0) {
        return null;
      }
      return Color(
        red: result.color_red,
        green: result.color_green,
        blue: result.color_blue,
      );
    });
  }

  StepSequencerValue readStepSequencerValue(String path) {
    return using((arena) {
      var ffiPath = path.toNativeUtf8(allocator: arena);
      FFIStepSequencerValue result = this
          ._bindings
          .read_step_sequencer_value(ptr, ffiPath.cast<ffi.Char>());

      var value = StepSequencerValue(
          result.value.asList().map((e) => e > 0).toList(), result.beat);

      this._bindings.drop_step_sequencer_value(result);

      return value;
    });
  }

  double readLevelValue(String path) {
    return using((arena) {
      var ffiPath = path.toNativeUtf8(allocator: arena);
      var result =
          this._bindings.read_level_value(ptr, ffiPath.cast<ffi.Char>());

      return result;
    });
  }

  @override
  List<LayoutReadValue> readLayoutValues(List<int> kinds, List<String> paths) {
    if (kinds.length != paths.length) {
      throw ArgumentError("kinds and paths must have the same length");
    }
    return using((arena) {
      final requests = arena<FFILayoutReadRequest>(kinds.length);
      for (var index = 0; index < kinds.length; index++) {
        final request = (requests + index).ref;
        request.path =
            paths[index].toNativeUtf8(allocator: arena).cast<ffi.Char>();
        request.kind = kinds[index];
      }
      final result = _bindings.read_layout_values(ptr, requests, kinds.length);
      try {
        return List.generate(result.len, (index) {
          final value = (result.array + index).ref;
          return LayoutReadValue(
            value: value.value,
            min: value.min,
            max: value.max,
            percentage: value.percentage == 1,
            hasColor: value.has_color == 1,
            red: value.color_red,
            green: value.color_green,
            blue: value.color_blue,
            label: value.label == ffi.nullptr
                ? ''
                : value.label.cast<Utf8>().toDartString(),
            steps: List<bool>.unmodifiable(value.steps.array
                .asTypedList(value.steps.len)
                .map((step) => step > 0)),
            beat: value.beat,
          );
        });
      } finally {
        _bindings.drop_layout_values(result);
      }
    });
  }

  @override
  void disposePointer(ffi.Pointer<LayoutRef> _ptr) {
    this._bindings.drop_layout_pointer(_ptr);
  }
}

/// Source of batched layout control values, one entry per requested path.
abstract class LayoutValuesSource {
  List<LayoutReadValue> readLayoutValues(List<int> kinds, List<String> paths);
}

class StepSequencerValue {
  final List<bool> values;
  final int beat;

  StepSequencerValue(this.values, this.beat);
}

class LayoutReadValue {
  final double value, min, max, red, green, blue;
  final bool percentage, hasColor;
  final String label;
  final List<bool> steps;
  final int beat;

  const LayoutReadValue({
    required this.value,
    required this.min,
    required this.max,
    required this.percentage,
    required this.hasColor,
    required this.red,
    required this.green,
    required this.blue,
    required this.label,
    required this.steps,
    required this.beat,
  });
}
