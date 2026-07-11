//! Shared data vocabulary — the strict data boundaries of the application.
//!
//! These types are passed through the `tokio::sync::broadcast` channel and
//! form the contract between the PTY layer, the concept engine, and the
//! terminal tasks. Every type is `Clone` so it can be fanned out to
//! multiple receivers.

use regex::Regex;

/// Identifies and labels a distinct terminal pane.
///
/// `id` must be unique across all terminals in a workspace.
/// `labels` are used by the concept engine to route actions — a terminal
/// only receives an action if its labels contain the action's `target_label`.
#[derive(Debug, Clone)]
pub struct TerminalConfig {
    pub id: u32,
    pub labels: Vec<String>,
}

/// The payload broadcast through the pub-sub channel when a concept triggers.
#[derive(Debug, Clone)]
pub struct Event {
    pub topic: String,
    pub payload: String,
    pub source_pane: u32,
    /// Regex capture groups from the trigger match (group 0 = full match).
    pub captures: Vec<String>,
}

/// A command to inject into a target terminal, gated by a label.
///
/// The `command_template` is written to the target PTY's stdin as-is
/// (with `\n` appended). Variable substitution (e.g., `{payload}`)
/// could be added in a future iteration.
#[derive(Debug, Clone)]
pub struct Action {
    pub command_template: String,
    /// Only terminals whose `TerminalConfig::labels` contain this label
    /// will receive and execute the command.
    pub target_label: String,
}

/// A business-logic concept: regex trigger → labelled actions.
///
/// Concepts are the core orchestration primitive. When a terminal produces
/// a line of output matching `trigger_regex`, every `Action` in `destinations`
/// is routed to terminals with the matching `target_label`.
///
/// # Example
///
/// ```ignore
/// Concept {
///     name: "port_conflict".into(),
///     trigger_regex: Regex::new(r"(?i)address.*already.*in\s*use").unwrap(),
///     destinations: vec![Action {
///         command_template: "echo 'Port conflict detected'".into(),
///         target_label: "observer".into(),
///     }],
/// }
/// ```
#[derive(Debug, Clone)]
pub struct Concept {
    pub name: String,
    pub trigger_regex: Regex,
    pub destinations: Vec<Action>,
}
