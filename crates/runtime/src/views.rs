//! Views to read pipeline internal values without locking
use std::collections::HashMap;
use std::sync::Arc;

use mizer_clock::Timecode;
use mizer_node::NodePath;
use mizer_ports::Color;
use pinboard::NonEmptyPinboard;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Dial {
    pub value: f64,
    pub min: f64,
    pub max: f64,
    pub percentage: bool,
}

impl Default for Dial {
    fn default() -> Self {
        Self {
            value: 0.0,
            min: 0.0,
            max: 1.0,
            percentage: true,
        }
    }
}

#[derive(Clone)]
pub struct LayoutsView {
    faders: Arc<NonEmptyPinboard<HashMap<NodePath, f64>>>,
    buttons: Arc<NonEmptyPinboard<HashMap<NodePath, bool>>>,
    dials: Arc<NonEmptyPinboard<HashMap<NodePath, Dial>>>,
    step_sequencers: Arc<NonEmptyPinboard<HashMap<NodePath, ([bool; 16], u8)>>>,
    labels: Arc<NonEmptyPinboard<HashMap<NodePath, Arc<String>>>>,
    colors: Arc<NonEmptyPinboard<HashMap<NodePath, Color>>>,
    clocks: Arc<NonEmptyPinboard<HashMap<NodePath, Timecode>>>,
    levels: Arc<NonEmptyPinboard<HashMap<NodePath, f64>>>,
}

impl Default for LayoutsView {
    fn default() -> Self {
        Self {
            faders: Arc::new(NonEmptyPinboard::new(Default::default())),
            buttons: Arc::new(NonEmptyPinboard::new(Default::default())),
            dials: Arc::new(NonEmptyPinboard::new(Default::default())),
            step_sequencers: Arc::new(NonEmptyPinboard::new(Default::default())),
            labels: Arc::new(NonEmptyPinboard::new(Default::default())),
            colors: Arc::new(NonEmptyPinboard::new(Default::default())),
            clocks: Arc::new(NonEmptyPinboard::new(Default::default())),
            levels: Arc::new(NonEmptyPinboard::new(Default::default())),
        }
    }
}

impl LayoutsView {
    pub fn get_fader_value(&self, path: &NodePath) -> Option<f64> {
        let values = self.faders.read();

        values.get(path).copied()
    }

    /// Skips the pinboard update when nothing changed; returns whether it wrote.
    pub(crate) fn write_fader_values(&self, values: HashMap<NodePath, f64>) -> bool {
        if *self.faders.get_ref() == values {
            return false;
        }
        self.faders.set(values);
        true
    }

    pub fn get_dial_value(&self, path: &NodePath) -> Option<Dial> {
        let values = self.dials.read();

        values.get(path).copied()
    }

    /// Skips the pinboard update when nothing changed; returns whether it wrote.
    pub(crate) fn write_dial_values(&self, values: HashMap<NodePath, Dial>) -> bool {
        if *self.dials.get_ref() == values {
            return false;
        }
        self.dials.set(values);
        true
    }

    pub fn get_button_value(&self, path: &NodePath) -> Option<bool> {
        let values = self.buttons.read();

        values.get(path).copied()
    }

    /// Skips the pinboard update when nothing changed; returns whether it wrote.
    pub(crate) fn write_button_values(&self, values: HashMap<NodePath, bool>) -> bool {
        if *self.buttons.get_ref() == values {
            return false;
        }
        self.buttons.set(values);
        true
    }

    pub fn get_label_value(&self, path: &NodePath) -> Option<Arc<String>> {
        let values = self.labels.read();

        values.get(path).cloned()
    }

    /// Skips the pinboard update when nothing changed; returns whether it wrote.
    pub(crate) fn write_label_values(&self, values: HashMap<NodePath, Arc<String>>) -> bool {
        if *self.labels.get_ref() == values {
            return false;
        }
        self.labels.set(values);
        true
    }

    /// Skips the pinboard update when nothing changed; returns whether it wrote.
    pub(crate) fn write_clock_values(&self, values: HashMap<NodePath, Timecode>) -> bool {
        if *self.clocks.get_ref() == values {
            return false;
        }
        self.clocks.set(values);
        true
    }

    pub fn get_clock_value(&self, path: &NodePath) -> Option<Timecode> {
        let values = self.clocks.read();

        values.get(path).copied()
    }

    /// Skips the pinboard update when nothing changed; returns whether it wrote.
    pub(crate) fn write_control_colors(&self, values: HashMap<NodePath, Color>) -> bool {
        if *self.colors.get_ref() == values {
            return false;
        }
        self.colors.set(values);
        true
    }

    pub fn get_control_color(&self, path: &NodePath) -> Option<Color> {
        let values = self.colors.read();

        values.get(path).copied()
    }

    pub fn get_step_sequencer_value(&self, path: &NodePath) -> Option<([bool; 16], u8)> {
        let values = self.step_sequencers.read();

        values.get(path).copied()
    }

    /// Skips the pinboard update when nothing changed; returns whether it wrote.
    pub(crate) fn write_step_sequencer_values(
        &self,
        values: HashMap<NodePath, ([bool; 16], u8)>,
    ) -> bool {
        if *self.step_sequencers.get_ref() == values {
            return false;
        }
        self.step_sequencers.set(values);
        true
    }

    pub fn get_level_value(&self, path: &NodePath) -> Option<f64> {
        let values = self.levels.read();

        values.get(path).copied()
    }

    /// Skips the pinboard update when nothing changed; returns whether it wrote.
    pub(crate) fn write_level_values(&self, values: HashMap<NodePath, f64>) -> bool {
        if *self.levels.get_ref() == values {
            return false;
        }
        self.levels.set(values);
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fader_map(value: f64) -> HashMap<NodePath, f64> {
        HashMap::from([(NodePath::from("/Fader 0"), value)])
    }

    #[test]
    fn unchanged_fader_values_skip_the_write() {
        let view = LayoutsView::default();

        assert!(view.write_fader_values(fader_map(0.5)));
        assert!(!view.write_fader_values(fader_map(0.5)));
        assert_eq!(view.get_fader_value(&NodePath::from("/Fader 0")), Some(0.5));
    }

    #[test]
    fn changed_fader_values_propagate_on_write() {
        let view = LayoutsView::default();
        view.write_fader_values(fader_map(0.5));

        assert!(view.write_fader_values(fader_map(0.75)));
        assert_eq!(
            view.get_fader_value(&NodePath::from("/Fader 0")),
            Some(0.75)
        );
    }

    #[test]
    fn unchanged_label_values_skip_the_write() {
        let view = LayoutsView::default();
        let labels =
            || HashMap::from([(NodePath::from("/Label 0"), Arc::new("hello".to_string()))]);

        assert!(view.write_label_values(labels()));
        assert!(!view.write_label_values(labels()));
        assert_eq!(
            view.get_label_value(&NodePath::from("/Label 0")),
            Some(Arc::new("hello".to_string()))
        );
    }

    #[test]
    fn changed_dial_values_propagate_on_write() {
        let view = LayoutsView::default();
        let dial = |value| Dial {
            value,
            ..Default::default()
        };
        let dials = |value| HashMap::from([(NodePath::from("/Dial 0"), dial(value))]);

        assert!(view.write_dial_values(dials(0.25)));
        assert!(!view.write_dial_values(dials(0.25)));
        assert!(view.write_dial_values(dials(0.5)));
        assert_eq!(
            view.get_dial_value(&NodePath::from("/Dial 0")),
            Some(dial(0.5))
        );
    }
}
