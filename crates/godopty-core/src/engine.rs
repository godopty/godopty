//! The central pub-sub orchestrator.
//!
//! [`WorkspaceEngine`] is the runtime coordinator. It owns the broadcast
//! channel, the concept registry, and spawns every terminal task (mock or
//! real-PTY-backed) as an isolated tokio task. Each task:
//!
//! 1. **Listens** for incoming [`Event`]s on the broadcast channel
//! 2. **Produces** events by running its output through [`crate::concept::match_and_broadcast`]
//! 3. **Injects** commands via the PTY writer when a matching event arrives

use std::sync::{Arc, Mutex};
use tokio::sync::{broadcast, mpsc};

use crate::concept;
use crate::term::TermGrid;
use crate::types::{Concept, Event, TerminalConfig};

// ── Stdin input discrimination ────────────────────────────────────────

/// Commands sent to a PTY from the outside (keyboard or concept actions).
enum StdinInput {
    Line(String),
    Raw(Vec<u8>),
    /// Resize the PTY — sends SIGWINCH to the child process.
    Resize { rows: u16, cols: u16 },
}

// ── Public types ──────────────────────────────────────────────────────

/// The central pub-sub orchestrator.
pub struct WorkspaceEngine {
    tx: broadcast::Sender<Event>,
    concepts: Arc<Vec<Concept>>,
}

/// A handle to a spawned PTY terminal, allowing the caller to inject input.
pub struct PtyTerminalHandle {
    pub id: u32,
    stdin_tx: mpsc::UnboundedSender<StdinInput>,
}

impl PtyTerminalHandle {
    /// Send a complete line to the PTY — `\n` is appended automatically.
    /// Used for concept-triggered action commands.
    pub fn send_line(&self, text: &str) {
        let _ = self.stdin_tx.send(StdinInput::Line(text.to_string()));
    }

    /// Send raw bytes to the PTY as-is (no newline appended).
    /// Used for interactive keyboard input — the shell's line discipline
    /// handles echo, backspace, and line buffering.
    pub fn send_text(&self, text: &str) {
        let _ = self.stdin_tx.send(StdinInput::Raw(text.as_bytes().to_vec()));
    }

    /// Resize the PTY — sends SIGWINCH to the child process.
    pub fn resize_pty(&self, rows: u16, cols: u16) {
        let _ = self.stdin_tx.send(StdinInput::Resize { rows, cols });
    }
}

/// A spawned terminal with both input control and a renderable grid.
pub struct SpawnedTerminal {
    pub handle: PtyTerminalHandle,
    pub grid: Arc<Mutex<TermGrid>>,
    _task: tokio::task::JoinHandle<()>,
}

// ── WorkspaceEngine ───────────────────────────────────────────────────

impl WorkspaceEngine {
    pub fn new(concepts: Vec<Concept>) -> Self {
        let (tx, _) = broadcast::channel(1024);
        Self { tx, concepts: Arc::new(concepts) }
    }

    /// Spawn a **mock** terminal task that cycles through mock output.
    pub async fn spawn_mock_terminal(
        &self,
        config: TerminalConfig,
        mock_outputs: Vec<String>,
        interval_ms: u64,
    ) {
        let mut rx = self.tx.subscribe();
        let tx = self.tx.clone();
        let concepts = Arc::clone(&self.concepts);
        let id = config.id;
        let labels = config.labels;

        tokio::spawn(async move {
            let mut interval =
                tokio::time::interval(tokio::time::Duration::from_millis(interval_ms));
            let mut idx = 0usize;
            loop {
                tokio::select! {
                    Ok(event) = rx.recv() => {
                        let commands =
                            concept::matching_commands(id, &labels, &concepts, &event);
                        for cmd in commands {
                            log::info!("[Pane {id}] Received '{:?}'. Would execute: {cmd}", event.topic);
                        }
                    }
                    _ = interval.tick() => {
                        if let Some(line) = mock_outputs.get(idx) {
                            concept::match_and_broadcast(id, &concepts, &tx, line);
                            idx = (idx + 1) % mock_outputs.len();
                        }
                    }
                }
            }
        });
    }

    /// Spawn a real-PTY terminal (text-only, no grid).
    pub async fn spawn_pty_terminal(
        &self,
        config: TerminalConfig,
        command: &str,
        args: &[&str],
    ) -> Result<PtyTerminalHandle, Box<dyn std::error::Error + Send + Sync>> {
        let (pty_tx, pty_rx) = mpsc::unbounded_channel::<Vec<u8>>();
        let pty_handle = crate::pty::PtyHandle::spawn(config.id, command, args, pty_tx)?;
        let (stdin_tx, stdin_rx) = mpsc::unbounded_channel::<StdinInput>();

        let task_ctx = TaskContext {
            id: config.id,
            labels: config.labels,
            concepts: Arc::clone(&self.concepts),
            rx: self.tx.subscribe(),
            tx: self.tx.clone(),
        };

        tokio::spawn(run_terminal_task(task_ctx, pty_handle, pty_rx, stdin_rx, None));

        Ok(PtyTerminalHandle { id: config.id, stdin_tx })
    }

    /// Spawn a terminal with both concept matching and a renderable grid.
    pub async fn spawn_terminal_with_grid(
        &self,
        config: TerminalConfig,
        command: &str,
        args: &[&str],
        rows: usize,
        cols: usize,
    ) -> Result<SpawnedTerminal, Box<dyn std::error::Error + Send + Sync>> {
        let (pty_tx, pty_rx) = mpsc::unbounded_channel::<Vec<u8>>();
        let pty_handle = crate::pty::PtyHandle::spawn(config.id, command, args, pty_tx)?;
        let (stdin_tx, stdin_rx) = mpsc::unbounded_channel::<StdinInput>();

        let grid = Arc::new(Mutex::new(TermGrid::new(rows, cols)));
        let grid_clone = Arc::clone(&grid);

        let task_ctx = TaskContext {
            id: config.id,
            labels: config.labels,
            concepts: Arc::clone(&self.concepts),
            rx: self.tx.subscribe(),
            tx: self.tx.clone(),
        };

        let task = tokio::spawn(run_terminal_task(
            task_ctx, pty_handle, pty_rx, stdin_rx, Some(grid_clone),
        ));

        Ok(SpawnedTerminal { handle: PtyTerminalHandle { id: config.id, stdin_tx }, grid, _task: task })
    }
}

// ── Shared terminal task ──────────────────────────────────────────────

/// Immutable context passed into every spawned terminal task.
struct TaskContext {
    id: u32,
    labels: Vec<String>,
    concepts: Arc<Vec<Concept>>,
    rx: broadcast::Receiver<Event>,
    tx: broadcast::Sender<Event>,
}

/// The shared async loop run by every terminal task.
///
/// Handles concept dispatch, PTY I/O, and optional grid updates.
/// When `grid` is `Some`, PTY output is also fed into the [`TermGrid`]
/// and resize commands update the grid dimensions.
async fn run_terminal_task(
    ctx: TaskContext,
    mut pty_handle: crate::pty::PtyHandle,
    mut pty_rx: mpsc::UnboundedReceiver<Vec<u8>>,
    mut stdin_rx: mpsc::UnboundedReceiver<StdinInput>,
    grid: Option<Arc<Mutex<TermGrid>>>,
) {
    let TaskContext { id, labels, concepts, mut rx, tx } = ctx;
    let mut line_parser = crate::parser::LineParser::new();

    loop {
        tokio::select! {
            msg = rx.recv() => {
                match msg {
                    Ok(event) => {
                        let commands = concept::matching_commands(id, &labels, &concepts, &event);
                        for cmd in commands {
                            let _ = pty_handle.write_line(&cmd);
                        }
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
                        log::warn!("[Pane {id}] Lagged behind broadcast channel, skipped {skipped} events");
                        continue;
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                }
            }
            msg = pty_rx.recv() => {
                let Some(bytes) = msg else { break; };
                let lines = line_parser.feed(&bytes);
                for line in lines {
                    concept::match_and_broadcast(id, &concepts, &tx, &line);
                }
                if let Some(g) = &grid {
                    if let Ok(mut locked) = g.lock() {
                        locked.feed(&bytes);
                    }
                }
            }
            msg = stdin_rx.recv() => {
                let Some(input) = msg else { break; };
                match input {
                    StdinInput::Line(line) => {
                        let _ = pty_handle.write_line(&line);
                    }
                    StdinInput::Raw(data) => {
                        let _ = pty_handle.write_bytes(&data);
                    }
                    StdinInput::Resize { rows, cols } => {
                        let _ = pty_handle.resize(rows, cols);
                        if let Some(g) = &grid {
                            if let Ok(mut locked) = g.lock() {
                                locked.resize(rows as usize, cols as usize);
                            }
                        }
                    }
                }
            }
        }
    }
}
