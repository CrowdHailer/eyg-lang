//// Compute provides durable execution of EYG programs against versioned filesystems.
//// 
//// A box owns an ordered history of accepted filesystem revisions. Multiple terminals may operate on the same box.
//// Accepted filesystem changes preserve the validity of EYG modules and their imports.
//// Reads are not tracked, so this is not serializable transaction isolation.
//// 
//// Execution proceeds in segments. Each segment starts from a recorded box revision.
//// Its accepted filesystem changes and execution outcome are recorded atomically. Recovery replays recorded segments against their recorded revisions; continued execution after an external response uses the latest revision.
////
//// Schedules and event bindings submit work through the same execution mechanism.
//// Assistance uses that mechanism to run agent tools.
//// 
//// A box can be cloned.
//// 
//// Terminals are code running against the file system.
//// A terminal will suspend when performing external work such as calling a web endpoint.
//// Continuing, once the work is concluded, will pin the new version of the file system.
//// 
//// Resumption is the processes of rebuilding a terminal into memory when a user returns to it.
//// This process is hidden from the user and all terminals appear live, unless explicitly deleted.
//// 
//// ## Shells, terminals and sessions
//// Bash is a shell, and one terminal running Bash is a shell session (an active instance of a shell running inside a terminal window or console).
//// So the shell is the program, a session is an instance and a terminal/console is a user surface
//// 
//// In Windows:
//// - Command Prompt — the traditional Windows command-line shell (cmd.exe).
//// - PowerShell — its newer shell and scripting language.
//// - Windows Terminal — the application that hosts PowerShell, Command Prompt, and other shells.
//// 
//// So the Shell is the program, no word for session/instance is used.
//// Terminal is commonly seen as the UI element.
//// 
//// Apple calls its macOS command-line application Terminal. 
//// The default shell inside it is zsh, but users generally see and open “Terminal.”
////  Apple also has an app called Console, which is for viewing system logs and diagnostic messages—not entering commands.
//// 
//// So Terminal is the consistent user-facing name across both macOS and modern Windows for a command-line interface.
//// 
//// Tmux uses the word session to describe a collection of windows that can be attached too.
//// An individual terminal is a pane (though we see it's easy to equate terminal to pane).
//// 
//// Familiarity with Tmux also supports using the term terminal for individual terminal instance.
//// And potentially the term session can be used in the tmux manner as a persistent setup across multiple terminals, and even boxes.
//// 
//// A terminal is a durable, sequential EYG evaluation context attached to one box.
//// Scope is maintained forever in a terminal, or until clear is called.
//// A terminal acts as a concurrency boundary and will process one code submission at a time.
//// 
//// In the web interface a terminal can be subscribed to and events are streamed to a client.
//// 
//// The term session was avoided because of web sessions and chat sessions, both outside this context but commonly used.
//// 
//// This bounded context does not check users/devices and their permission against workspaces, that is handled by `Access`.
//// The routes into this domain reflect this.
//// POST /boxes creates a new box in the organisation designated by the token.
//// 
//// This bounded context does not implement any chat or agent
//// This is built on top of the compute substrate. (substrate is a good name)
//// The `Assistance` context implements chats/agents.
//// 
//// Secrets are stored per organisation.

import gleam/option.{type Option}

pub type Box {
  Box(name: Option(String), pointer: Pointer)
}

/// Combination of an ID and a sequence for an event stream
pub type Pointer {
  Pointer(id: String, sequence: Int)
}

pub fn list_boxes(_workspace_id: String) {
  // SELECT all named boxes within a workspace
  panic as "unimplemented"
}

/// Create a new named box, takes 
pub fn create_box(_workspace_id: String, _name: String, _source: Option(Box)) {
  panic as "unimplemented"
}

pub fn write_file(_ref: Pointer, _path: String, _bytes: BitArray) {
  panic as "unimplemented"
}

/// Start an unbounded terminal.
/// Every terminal belongs to exactly one box. Starting a terminal without selecting a box creates an unnamed box.
/// POST /terminals
pub fn start_terminal(_workspace_id: String) {
  panic as "unimplemented"
}

/// Start a terminal on a box
/// POST /box_/:box_id/terminals
pub fn start_terminal_in_box(_box_id: String) {
  panic as "unimplemented"
}

/// Stop any work a terminal is currently doing.
/// This commits an event into the terminal history so it is not restarted
pub fn halt_terminal(_terminal_id: String) {
  panic as "unimplemented"
}
