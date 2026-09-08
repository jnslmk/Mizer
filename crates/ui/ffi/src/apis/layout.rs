use crate::apis::transport::Timecode;
use crate::types::{drop_array, drop_pointer, Array, FFIFromPointer};
use mizer_node::NodePath;
use mizer_runtime::LayoutsView;
use parking_lot::Mutex;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Arc;

pub struct LayoutRef {
    pub view: LayoutsView,
    // ponytail: one retained CString per label path; readers copy it synchronously per read.
    labels: Mutex<HashMap<NodePath, CString>>,
}

impl LayoutRef {
    pub fn new(view: LayoutsView) -> Self {
        Self {
            view,
            labels: Default::default(),
        }
    }

    fn store_label(&self, path: &NodePath, value: String) -> *const c_char {
        let value = CString::new(value).unwrap();
        let pointer = value.as_ptr();
        self.labels.lock().insert(path.clone(), value);
        pointer
    }
}

#[no_mangle]
pub extern "C" fn read_fader_value(ptr: *const LayoutRef, path: *const c_char) -> f64 {
    let path = unsafe { CStr::from_ptr(path) };
    let path = path.to_str().unwrap();
    let node_path = NodePath::from(path);
    let ffi = Arc::from_pointer(ptr);

    let value = ffi.view.get_fader_value(&node_path).unwrap_or_default();

    std::mem::forget(ffi);

    value
}

#[no_mangle]
pub extern "C" fn read_dial_value(ptr: *const LayoutRef, path: *const c_char) -> FFIDialValue {
    let path = unsafe { CStr::from_ptr(path) };
    let path = path.to_str().unwrap();
    let node_path = NodePath::from(path);
    let ffi = Arc::from_pointer(ptr);

    let value = ffi.view.get_dial_value(&node_path).unwrap_or_default();
    let ffi_value = FFIDialValue {
        value: value.value,
        min: value.min,
        max: value.max,
        is_percentage: if value.percentage { 1 } else { 0 },
    };

    std::mem::forget(ffi);

    ffi_value
}

#[no_mangle]
pub extern "C" fn read_button_value(ptr: *const LayoutRef, path: *const c_char) -> u8 {
    let path = unsafe { CStr::from_ptr(path) };
    let path = path.to_str().unwrap();
    let node_path = NodePath::from(path);
    let ffi = Arc::from_pointer(ptr);

    let value = ffi.view.get_button_value(&node_path).unwrap_or_default();

    std::mem::forget(ffi);

    value.into()
}

#[no_mangle]
pub extern "C" fn read_label_value(ptr: *const LayoutRef, path: *const c_char) -> *const c_char {
    let path = unsafe { CStr::from_ptr(path) };
    let path = path.to_str().unwrap();
    let node_path = NodePath::from(path);
    let ffi = Arc::from_pointer(ptr);

    let value = ffi.view.get_label_value(&node_path).unwrap_or_default();
    let value_pointer = ffi.store_label(&node_path, value.to_string());

    std::mem::forget(ffi);

    value_pointer
}

#[no_mangle]
pub extern "C" fn read_clock_value(ptr: *const LayoutRef, path: *const c_char) -> Timecode {
    let path = unsafe { CStr::from_ptr(path) };
    let path = path.to_str().unwrap();
    let node_path = NodePath::from(path);
    let ffi = Arc::from_pointer(ptr);

    let value = ffi.view.get_clock_value(&node_path).unwrap_or_default();

    std::mem::forget(ffi);

    value.into()
}

#[no_mangle]
pub extern "C" fn read_control_color(
    ptr: *const LayoutRef,
    path: *const c_char,
) -> FFIControlColor {
    let path = unsafe { CStr::from_ptr(path) };
    let path = path.to_str().unwrap();
    let node_path = NodePath::from(path);
    let ffi = Arc::from_pointer(ptr);

    let value = if let Some(value) = ffi.view.get_control_color(&node_path) {
        FFIControlColor {
            has_color: 1,
            color_red: value.red,
            color_green: value.green,
            color_blue: value.blue,
        }
    } else {
        FFIControlColor {
            has_color: 0,
            color_red: 0.,
            color_green: 0.,
            color_blue: 0.,
        }
    };

    std::mem::forget(ffi);

    value
}

#[no_mangle]
pub extern "C" fn read_step_sequencer_value(ptr: *const LayoutRef, path: *const c_char) -> FFIStepSequencerValue {
    let path = unsafe { CStr::from_ptr(path) };
    let path = path.to_str().unwrap();
    let node_path = NodePath::from(path);
    let ffi = Arc::from_pointer(ptr);

    let (value, beat) = ffi.view.get_step_sequencer_value(&node_path).unwrap_or_default();
    let value = value.into_iter().map(|v| v as u8).collect();

    std::mem::forget(ffi);

    FFIStepSequencerValue { value, beat }
}

#[no_mangle]
pub extern "C" fn read_level_value(ptr: *const LayoutRef, path: *const c_char) -> f64 {
    let path = unsafe { CStr::from_ptr(path) };
    let path = path.to_str().unwrap();
    let node_path = NodePath::from(path);
    let ffi = Arc::from_pointer(ptr);

    let value = ffi.view.get_level_value(&node_path).unwrap_or_default();

    std::mem::forget(ffi);

    value
}


#[no_mangle]
pub extern "C" fn read_layout_values(
    ptr: *const LayoutRef,
    requests: *const FFILayoutReadRequest,
    len: usize,
) -> Array<FFILayoutValue> {
    let ffi = Arc::from_pointer(ptr);
    let requests = unsafe { std::slice::from_raw_parts(requests, len) };
    let values = requests
        .iter()
        .map(|request| {
            let path = unsafe { CStr::from_ptr(request.path) }.to_str().unwrap();
            let path = NodePath::from(path);
            match request.kind {
                0 => FFILayoutValue::number(ffi.view.get_fader_value(&path).unwrap_or_default()),
                1 => {
                    let value = ffi.view.get_dial_value(&path).unwrap_or_default();
                    FFILayoutValue {
                        value: value.value,
                        min: value.min,
                        max: value.max,
                        percentage: value.percentage.into(),
                        ..Default::default()
                    }
                }
                2 => {
                    let color = ffi.view.get_control_color(&path);
                    FFILayoutValue {
                        value: ffi.view.get_button_value(&path).unwrap_or_default().into(),
                        has_color: color.is_some().into(),
                        color_red: color.map_or(0., |color| color.red),
                        color_green: color.map_or(0., |color| color.green),
                        color_blue: color.map_or(0., |color| color.blue),
                        ..Default::default()
                    }
                }
                3 => {
                    let label = ffi.store_label(&path, ffi.view.get_label_value(&path).unwrap_or_default().to_string());
                    FFILayoutValue { label, ..Default::default() }
                }
                4 => {
                    let (steps, beat) = ffi.view.get_step_sequencer_value(&path).unwrap_or_default();
                    FFILayoutValue {
                        steps: steps.into_iter().map(|step| step as u8).collect(),
                        beat,
                        ..Default::default()
                    }
                }
                5 => FFILayoutValue::number(ffi.view.get_level_value(&path).unwrap_or_default()),
                _ => Default::default(),
            }
        })
        .collect();
    std::mem::forget(ffi);
    values
}

#[no_mangle]
pub extern "C" fn drop_layout_values(values: Array<FFILayoutValue>) {
    for value in values.into_vec() {
        drop_array(value.steps);
    }
}

#[no_mangle]
pub extern "C" fn drop_layout_pointer(ptr: *const LayoutRef) {
    drop_pointer(ptr);
}

#[no_mangle]
pub extern "C" fn drop_step_sequencer_value(value: FFIStepSequencerValue) {
    drop_array(value.value);
}

#[repr(C)]
pub struct FFILayoutReadRequest {
    pub path: *const c_char,
    pub kind: u8,
}

#[repr(C)]
pub struct FFILayoutValue {
    pub value: f64,
    pub min: f64,
    pub max: f64,
    pub percentage: u8,
    pub has_color: u8,
    pub color_red: f64,
    pub color_green: f64,
    pub color_blue: f64,
    pub label: *const c_char,
    pub steps: Array<u8>,
    pub beat: u8,
}

impl FFILayoutValue {
    fn number(value: f64) -> Self {
        Self { value, ..Default::default() }
    }
}

impl Default for FFILayoutValue {
    fn default() -> Self {
        Self {
            value: 0.,
            min: 0.,
            max: 0.,
            percentage: 0,
            has_color: 0,
            color_red: 0.,
            color_green: 0.,
            color_blue: 0.,
            label: std::ptr::null(),
            steps: Vec::new().into(),
            beat: 0,
        }
    }
}

#[derive(Default)]
#[repr(C)]
pub struct FFIControlColor {
    pub has_color: u8,
    pub color_red: f64,
    pub color_green: f64,
    pub color_blue: f64,
}

#[derive(Default)]
#[repr(C)]
pub struct FFIDialValue {
    pub value: f64,
    pub min: f64,
    pub max: f64,
    pub is_percentage: u8,
}

#[repr(C)]
pub struct FFIStepSequencerValue {
    pub value: Array<u8>,
    pub beat: u8,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> (*const LayoutRef, CString) {
        let layout = Arc::new(LayoutRef::new(LayoutsView::default()));
        (Arc::into_raw(layout), CString::new("/Label 0").unwrap())
    }

    fn batch_label_read(ptr: *const LayoutRef, path: &CString) -> Array<FFILayoutValue> {
        let request = FFILayoutReadRequest {
            path: path.as_ptr(),
            kind: 3,
        };
        read_layout_values(ptr, &request, 1)
    }

    fn label_count(ptr: *const LayoutRef) -> usize {
        unsafe { &*ptr }.labels.lock().len()
    }

    #[test]
    fn repeated_batch_label_reads_keep_retention_bounded() {
        let (ptr, path) = fixture();

        let values = batch_label_read(ptr, &path).into_vec();
        assert_eq!(unsafe { CStr::from_ptr(values[0].label) }.to_str().unwrap(), "");
        drop_layout_values(values.into());
        let baseline = label_count(ptr);
        for _ in 0..1000 {
            drop_layout_values(batch_label_read(ptr, &path));
        }

        assert_eq!(label_count(ptr), baseline);
        drop_layout_pointer(ptr);
    }

    #[test]
    fn repeated_single_label_reads_keep_retention_bounded() {
        let (ptr, path) = fixture();

        let label = read_label_value(ptr, path.as_ptr());
        assert_eq!(unsafe { CStr::from_ptr(label) }.to_str().unwrap(), "");
        let baseline = label_count(ptr);
        for _ in 0..1000 {
            read_label_value(ptr, path.as_ptr());
        }

        assert_eq!(label_count(ptr), baseline);
        drop_layout_pointer(ptr);
    }
}
