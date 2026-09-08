use std::collections::HashMap;
use std::ops::{Deref, DerefMut};
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::Duration;

use itertools::Itertools;
use pinboard::NonEmptyPinboard;

use mizer_clock::{BoxedClock, Clock, ClockSnapshot, SystemClock};
use mizer_debug_ui_impl::*;
use mizer_fixtures::manager::FixtureManager;
use mizer_fixtures::programmer::PresetId;
use mizer_layouts::{ControlConfig, ControlType, Layout, LayoutStorage};
use mizer_message_bus::MessageBus;
use mizer_module::Runtime;
use mizer_node::*;
use mizer_nodes::*;
use mizer_pipeline::*;
use mizer_plan::PlanStorage;
use mizer_processing::*;
use mizer_project_files::{Project, ProjectManagerMut};
use mizer_status_bus::StatusBus;

use crate::api::RuntimeAccess;
use crate::{LayoutsView, NodeMetadataRef, Pipeline};

const DEFAULT_FPS: f64 = 60.0;

pub struct CoordinatorRuntime {
    layouts: LayoutStorage,
    plans: PlanStorage,
    injector: Injector,
    processors: Vec<Box<dyn Processor>>,
    clock_recv: flume::Receiver<ClockSnapshot>,
    clock_sender: flume::Sender<ClockSnapshot>,
    clock_snapshot: Arc<NonEmptyPinboard<ClockSnapshot>>,
    layout_fader_view: LayoutsView,
    node_metadata: Arc<NonEmptyPinboard<HashMap<NodePath, NodeRuntimeMetadata>>>,
    status_bus: StatusBus,
    read_node_metadata: Arc<AtomicBool>,
    read_node_settings: Arc<NonEmptyPinboard<Vec<NodePath>>>,
    node_settings_bus: MessageBus<HashMap<NodePath, Vec<NodeSetting>>>,
}

impl CoordinatorRuntime {
    pub fn new() -> Self {
        let clock = SystemClock::default();

        Self::with_clock(clock)
    }
}

impl CoordinatorRuntime {
    pub fn with_clock<TClock: Clock + 'static>(clock: TClock) -> CoordinatorRuntime {
        let (clock_tx, clock_rx) = flume::unbounded();
        let snapshot = clock.snapshot();
        let node_metadata = Arc::new(NonEmptyPinboard::new(Default::default()));
        let mut runtime = Self {
            layouts: NonEmptyPinboard::new(Default::default()).into(),
            plans: NonEmptyPinboard::new(Default::default()).into(),
            injector: Default::default(),
            processors: Default::default(),
            clock_recv: clock_rx,
            clock_sender: clock_tx,
            clock_snapshot: NonEmptyPinboard::new(snapshot).into(),
            layout_fader_view: Default::default(),
            node_metadata,
            status_bus: Default::default(),
            read_node_metadata: Arc::new(AtomicBool::new(false)),
            read_node_settings: NonEmptyPinboard::new(Default::default()).into(),
            node_settings_bus: Default::default(),
        };
        runtime.bootstrap(Box::new(clock));

        runtime
    }

    fn bootstrap(&mut self, clock: BoxedClock) {
        self.injector.provide(self.plans.clone());
        self.injector.provide(self.layouts.clone());
        self.injector.provide(clock);
    }

    fn add_layouts(&self, layouts: impl IntoIterator<Item = (String, Vec<ControlConfig>)>) {
        let layouts = layouts
            .into_iter()
            .map(|(id, controls)| Layout { id, controls })
            .collect();

        self.layouts.set(layouts);
    }

    pub fn generate_pipeline_graph(&self) -> anyhow::Result<()> {
        let pipeline = self.injector.inject::<Pipeline>();
        pipeline.generate_pipeline_graph()?;

        Ok(())
    }

    pub fn provide<T: 'static>(&mut self, service: T) {
        self.injector.provide(service);
    }

    pub fn access(&self) -> RuntimeAccess {
        RuntimeAccess {
            layouts: self.layouts.clone(),
            plans: self.plans.clone(),
            clock_recv: self.clock_recv.clone(),
            clock_snapshot: self.clock_snapshot.clone(),
            layouts_view: self.layout_fader_view.clone(),
            status_bus: self.status_bus.clone(),
            read_node_metadata: self.read_node_metadata.clone(),
            read_node_settings: self.read_node_settings.clone(),
            node_settings_bus: self.node_settings_bus.clone(),
        }
    }

    pub fn get_preview_ref(&self, path: &NodePath) -> Option<NodePreviewRef> {
        self.injector.inject::<Pipeline>().get_preview_ref(path)
    }

    pub fn get_node_metadata_ref(&self) -> NodeMetadataRef {
        NodeMetadataRef::new(Arc::clone(&self.node_metadata))
    }

    #[profiling::function]
    pub(crate) fn read_states_into_view(&self) -> usize {
        let pipeline = self.injector.inject::<Pipeline>();
        // Classify each layout control path by node type once, so the per-kind
        // passes below only touch the nodes they can actually read instead of
        // probing every path against every control node type each tick.
        // ponytail: per-tick rebuild, no cache; layouts are small and a cache
        // would need invalidation plumbing for identical output.
        let mut fader_paths = Vec::new();
        let mut dial_paths = Vec::new();
        let mut button_paths = Vec::new();
        let mut label_paths = Vec::new();
        let mut clock_paths = Vec::new();
        let mut step_sequencer_paths = Vec::new();
        let mut level_paths = Vec::new();
        {
            let layouts = self.layouts.get_ref();
            let paths = layouts
                .iter()
                .flat_map(|layout| &layout.controls)
                .filter_map(|control| match &control.control_type {
                    ControlType::Node { path } => Some(path.clone()),
                    _ => None,
                })
                .sorted()
                .dedup()
                .collect::<Vec<_>>();
            for path in &paths {
                let node_type = pipeline.get_node_dyn(path).map(|node| node.node_type());
                match node_type {
                    Some(NodeType::Fader) => fader_paths.push(path.clone()),
                    Some(NodeType::Dial) => dial_paths.push(path.clone()),
                    Some(NodeType::Button) => button_paths.push(path.clone()),
                    Some(NodeType::Label) => label_paths.push(path.clone()),
                    Some(NodeType::Timecode) => clock_paths.push(path.clone()),
                    Some(NodeType::StepSequencer) => step_sequencer_paths.push(path.clone()),
                    Some(NodeType::Level) => level_paths.push(path.clone()),
                    _ => {}
                }
            }
        }
        let mut changed = 0;

        let fader_values = fader_paths
            .iter()
            .filter_map(|path| {
                pipeline
                    .get_node_with_state::<FaderNode>(path)
                    .map(|(node, state)| node.value(state))
                    .map(|value| (path.clone(), value))
            })
            .collect::<HashMap<_, _>>();

        changed += self.layout_fader_view.write_fader_values(fader_values) as usize;

        let dial_values = dial_paths
            .iter()
            .filter_map(|path| {
                pipeline
                    .get_node_with_state::<DialNode>(path)
                    .map(|(node, state)| {
                        let value = node.value(state);
                        let (min, max) = node.range();
                        let percentage = node.percentage();

                        crate::views::Dial {
                            value,
                            min,
                            max,
                            percentage,
                        }
                    })
                    .map(|value| (path.clone(), value))
            })
            .collect::<HashMap<_, _>>();
        changed += self.layout_fader_view.write_dial_values(dial_values) as usize;

        let button_values = button_paths
            .iter()
            .filter_map(|path| {
                pipeline
                    .get_node_with_state::<ButtonNode>(path)
                    .map(|(node, state)| node.value(state))
                    .map(|value| (path.clone(), value))
            })
            .collect::<HashMap<_, _>>();

        changed += self.layout_fader_view.write_button_values(button_values) as usize;

        let label_values = label_paths
            .iter()
            .filter_map(|path| {
                pipeline
                    .get_node_with_state::<LabelNode>(path)
                    .map(|(node, state)| node.label(state))
                    .map(|value| (path.clone(), value))
            })
            .collect::<HashMap<_, _>>();

        changed += self.layout_fader_view.write_label_values(label_values) as usize;

        let clock_values = clock_paths
            .iter()
            .filter_map(|path| {
                pipeline
                    .get_node_with_state::<TimecodeNode>(path)
                    .and_then(|(node, state)| node.timecode(state))
                    .map(|value| (path.clone(), value))
            })
            .collect::<HashMap<_, _>>();

        changed += self.layout_fader_view.write_clock_values(clock_values) as usize;

        let button_colors = button_paths
            .iter()
            .filter_map(|path| {
                pipeline
                    .get_node_with_state::<ButtonNode>(path)
                    .and_then(|(node, state)| node.color(state))
                    .map(|value| (path.clone(), value))
            })
            .collect::<HashMap<_, _>>();

        changed += self.layout_fader_view.write_control_colors(button_colors) as usize;

        let step_sequencer_values = step_sequencer_paths
            .iter()
            .filter_map(|path| {
                pipeline
                    .get_node_with_state::<StepSequencerNode>(path)
                    .map(|(node, state)| (path.clone(), (node.value(state), node.beat(state))))
            })
            .collect::<HashMap<_, _>>();

        changed += self
            .layout_fader_view
            .write_step_sequencer_values(step_sequencer_values) as usize;

        let level_values = level_paths
            .iter()
            .filter_map(|path| {
                pipeline
                    .get_node_with_state::<LevelNode>(path)
                    .map(|(node, state)| node.value(state))
                    .map(|value| (path.clone(), value))
            })
            .collect::<HashMap<_, _>>();

        changed += self.layout_fader_view.write_level_values(level_values) as usize;

        changed
    }

    fn get_preset_ids(&self) -> Vec<PresetId> {
        let fixture_manager = self.injector.get::<FixtureManager>().unwrap();
        fixture_manager
            .presets
            .color_presets()
            .into_iter()
            .map(|(id, _)| id)
            .chain(
                fixture_manager
                    .presets
                    .intensity_presets()
                    .into_iter()
                    .map(|(id, _)| id),
            )
            .chain(
                fixture_manager
                    .presets
                    .shutter_presets()
                    .into_iter()
                    .map(|(id, _)| id),
            )
            .chain(
                fixture_manager
                    .presets
                    .position_presets()
                    .into_iter()
                    .map(|(id, _)| id),
            )
            .collect()
    }

    #[profiling::function]
    pub(crate) fn read_node_settings(&mut self, paths: &[NodePath]) {
        // The watched-settings set is empty most ticks; skip the pipeline
        // refresh and still publish the (empty) settings so subscribers see
        // the same event they would have without the gate.
        let settings = if paths.is_empty() {
            HashMap::new()
        } else {
            let (pipeline, injector) = self.injector.get_slice_mut::<Pipeline>().unwrap();
            pipeline.refresh_settings(injector, paths);
            pipeline.get_settings(paths)
        };
        self.node_settings_bus.send(settings);
    }

    #[profiling::function]
    pub(crate) fn read_node_metadata(&mut self) {
        let (pipeline, injector) = self.injector.get_slice_mut::<Pipeline>().unwrap();
        pipeline.refresh_metadata(injector);
    }

    /// Should only be used for testing purposes
    // TODO: this should be private, the implementation of the nodes test is such a huge smell regarding app architecture
    #[doc(hidden)]
    #[profiling::function]
    pub fn read_node_ports(&mut self) {
        let (pipeline, injector) = self.injector.get_slice_mut::<Pipeline>().unwrap();
        pipeline.refresh_ports(injector);
    }

    pub fn clock(&self) -> &dyn Clock {
        self.injector.inject::<BoxedClock>().deref()
    }

    pub fn clock_mut(&mut self) -> &mut dyn Clock {
        self.injector.get_mut::<BoxedClock>().unwrap().deref_mut()
    }
}

impl Runtime for CoordinatorRuntime {
    fn injector_mut(&mut self) -> &mut Injector {
        &mut self.injector
    }

    fn injector(&self) -> &Injector {
        &self.injector
    }

    fn add_processor(&mut self, processor: impl Processor + 'static) {
        self.processors.push(Box::new(processor));
    }

    fn process(&mut self) {
        profiling::scope!("CoordinatorRuntime::process");
        tracing::trace!("tick");
        let (frame, snapshot, fps) = {
            let clock = self.clock_mut();
            let frame = clock.tick();
            let snapshot = clock.snapshot();
            let fps = clock.fps();

            (frame, snapshot, fps)
        };
        if let Err(err) = self.clock_sender.send(snapshot) {
            tracing::error!("Could not send clock snapshot {:?}", err);
        }
        self.clock_snapshot.set(snapshot);
        tracing::trace!("pre_process");
        for processor in self
            .processors
            .iter_mut()
            .sorted_by_key(|processor| processor.priorities().pre_process)
        {
            processor.pre_process(&mut self.injector, frame, fps);
        }
        tracing::trace!("process");
        for processor in self
            .processors
            .iter_mut()
            .sorted_by_key(|processor| processor.priorities().process)
        {
            processor.process(&mut self.injector, frame);
        }
        tracing::trace!("post_process");
        for processor in self
            .processors
            .iter_mut()
            .sorted_by_key(|processor| processor.priorities().post_process)
        {
            processor.post_process(&mut self.injector, frame);
        }
        let paths = self.read_node_settings.get_ref();
        self.read_node_settings(&paths);
        if self
            .read_node_metadata
            .load(std::sync::atomic::Ordering::Relaxed)
        {
            self.read_node_metadata();
            self.read_node_ports();
        }
        if let Some((ui, injector)) = self.injector.get_slice_mut::<DebugUiImpl>() {
            tracing::trace!("Update Debug UI");
            let mut render_handle = ui.pre_render();
            let pipeline = injector.inject::<Pipeline>();
            render_handle.draw(injector, pipeline);

            ui.render();
        }
        self.read_states_into_view();
    }

    fn add_status_message(&self, message: impl Into<String>, timeout: Option<Duration>) {
        self.status_bus.add_status_message(message, timeout);
    }

    fn fps(&self) -> f64 {
        self.clock().fps()
    }

    fn set_fps(&mut self, fps: f64) {
        let clock = self.clock_mut();
        *clock.fps_mut() = fps;
    }
}

impl ProjectManagerMut for CoordinatorRuntime {
    fn new_project(&mut self) {
        profiling::scope!("CoordinatorRuntime::new_project");
        self.set_fps(DEFAULT_FPS);
        let preset_ids = self.get_preset_ids();
        let (pipeline, injector) = self.injector.get_slice_mut::<Pipeline>().unwrap();
        pipeline.new_project(injector);
        for preset_id in preset_ids {
            pipeline
                .add_node(
                    injector,
                    NodeType::Preset,
                    NodeDesigner {
                        hidden: true,
                        ..Default::default()
                    },
                    Some(Node::Preset(PresetNode { id: preset_id })),
                    None,
                )
                .unwrap();
        }
    }

    fn load(&mut self, project: &Project) -> anyhow::Result<()> {
        profiling::scope!("CoordinatorRuntime::load");
        self.set_fps(project.playback.fps);
        let (pipeline, injector) = self.injector.get_slice_mut::<Pipeline>().unwrap();
        pipeline.load(project, injector)?;
        self.add_layouts(project.layouts.clone());
        self.plans.set(project.plans.clone());
        Ok(())
    }

    fn save(&self, project: &mut Project) {
        profiling::scope!("CoordinatorRuntime::save");
        project.playback.fps = self.fps();
        let pipeline = self.injector.inject::<Pipeline>();
        pipeline.save(project);
        project.layouts = self
            .layouts
            .read()
            .into_iter()
            .map(|layout| (layout.id, layout.controls))
            .collect();
        project.plans = self.plans.read();
    }

    fn clear(&mut self) {
        self.set_fps(DEFAULT_FPS);
        let pipeline = self.injector.get_mut::<Pipeline>().unwrap();
        pipeline.clear();
        self.layouts.set(vec![Layout {
            id: "Default".into(),
            controls: Vec::new(),
        }]);
        self.plans.set(Default::default());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn node_runner_should_lend_state_ref() {
        let mut runner = CoordinatorRuntime::new();
        let mut pipeline = Pipeline::new();
        let node = pipeline
            .add_node(
                runner.injector(),
                NodeType::Fader,
                Default::default(),
                Default::default(),
                Default::default(),
            )
            .unwrap();
        runner.injector.provide(pipeline);

        runner.process();

        let pipeline = runner.injector.inject::<Pipeline>();
        let state = pipeline
            .read_state::<<FaderNode as ProcessingNode>::State>(&node.path)
            .unwrap();
        assert_eq!(state, &None);
    }

    fn setup_static_layout_runner() -> (CoordinatorRuntime, NodePath) {
        use mizer_layouts::{ControlBehavior, ControlDecorations, ControlPosition, ControlSize};

        let mut runner = CoordinatorRuntime::new();
        let mut pipeline = Pipeline::new();
        let descriptor = pipeline
            .add_node(
                runner.injector(),
                NodeType::Fader,
                Default::default(),
                Default::default(),
                Default::default(),
            )
            .unwrap();
        let path = descriptor.path.clone();
        runner.injector.provide(pipeline);
        let controls = vec![ControlConfig {
            id: Default::default(),
            label: None,
            control_type: ControlType::Node { path: path.clone() },
            position: ControlPosition::default(),
            size: ControlSize::default(),
            decoration: ControlDecorations::default(),
            behavior: ControlBehavior::default(),
            hotkey: None,
        }];
        runner.add_layouts([("show".to_string(), controls)]);
        (runner, path)
    }

    #[test]
    fn idle_tick_skips_view_writes_when_nothing_changed() {
        let (mut runner, _) = setup_static_layout_runner();
        runner.process();

        assert_eq!(runner.read_states_into_view(), 0);
    }

    #[test]
    fn changed_value_propagates_in_the_same_tick() {
        let (mut runner, path) = setup_static_layout_runner();
        runner.process();
        let view = runner.access().layouts_view.clone();
        assert_eq!(view.get_fader_value(&path), Some(0.0));

        let pipeline = runner.injector.get_mut::<Pipeline>().unwrap();
        pipeline
            .get_node_mut::<FaderNode>(&path)
            .unwrap()
            .default_value = 0.75;
        runner.process();

        assert_eq!(view.get_fader_value(&path), Some(0.75));
        assert_eq!(runner.read_states_into_view(), 0);
    }

    #[test]
    #[ignore]
    fn profile_static_tick() {
        use std::time::Instant;

        use mizer_layouts::{ControlBehavior, ControlDecorations, ControlPosition, ControlSize};

        let mut runner = CoordinatorRuntime::new();
        let mut pipeline = Pipeline::new();
        let mut paths = Vec::new();
        for node_type in [NodeType::Fader, NodeType::Dial, NodeType::Button] {
            for _ in 0..8 {
                let descriptor = pipeline
                    .add_node(
                        runner.injector(),
                        node_type,
                        Default::default(),
                        Default::default(),
                        Default::default(),
                    )
                    .unwrap();
                paths.push(descriptor.path);
            }
        }
        runner.injector.provide(pipeline);
        let controls = paths
            .into_iter()
            .map(|path| ControlConfig {
                id: Default::default(),
                label: None,
                control_type: ControlType::Node { path },
                position: ControlPosition::default(),
                size: ControlSize::default(),
                decoration: ControlDecorations::default(),
                behavior: ControlBehavior::default(),
                hotkey: None,
            })
            .collect();
        runner.add_layouts([("show".to_string(), controls)]);

        for _ in 0..200 {
            runner.process();
        }
        let iters = 2000u32;
        let bench = |label: &str, f: &mut dyn FnMut()| {
            let start = Instant::now();
            for _ in 0..iters {
                f();
            }
            let per_tick = start.elapsed() / iters;
            println!("profile: {label} = {per_tick:?} per tick");
            per_tick
        };
        let full = bench("process", &mut || runner.process());
        let views = bench("read_states_into_view", &mut || {
            runner.read_states_into_view();
        });
        let settings = bench("read_node_settings_empty", &mut || {
            runner.read_node_settings(&[])
        });
        let layouts_clone = bench("layouts_read_clone", &mut || {
            std::hint::black_box(runner.layouts.read());
        });
        let clock_push = bench("clock_send_and_pinboard_set", &mut || {
            let snapshot = runner.clock().snapshot();
            std::hint::black_box(runner.clock_sender.send(snapshot)).unwrap();
            runner.clock_snapshot.set(snapshot);
        });
        // Drain the extra snapshots pushed by the clock_push bench above.
        while runner.clock_recv.try_recv().is_ok() {}
        println!(
            "profile: share views={:.1}% settings={:.1}% layouts_clone={:.1}% clock_push={:.1}% of process",
            views.as_nanos() as f64 / full.as_nanos() as f64 * 100.0,
            settings.as_nanos() as f64 / full.as_nanos() as f64 * 100.0,
            layouts_clone.as_nanos() as f64 / full.as_nanos() as f64 * 100.0,
            clock_push.as_nanos() as f64 / full.as_nanos() as f64 * 100.0,
        );
    }
}
