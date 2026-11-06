//// The terminal for one session, as a Lustre server component.
////
//// Commands are written with the structural editor in `cloud/editor`.
//// The page script (`cloud/web/script`) turns key presses and pastes
//// on the terminal into `eyg-key` and `eyg-paste` events, deciding in the
//// browser which keys keep their default. Everything visible is rendered
//// on the server as text in a `<pre>`.

import cloud/code
import cloud/editor.{type Editor}
import cloud/editor/combobox
import cloud/fs
import cloud/modules
import cloud/sessions.{type Session, type Sessions, Step}
import cloud/shell
import cloud/terminal
import cloud/terminal/html as term_html
import etui/span.{type Line}
import etui/style
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre/server_component
import morph/buffer
import morph/editable as e
import morph/projection
import multiformats/cid/v1

/// Longest a command may run before it is stopped.
pub const time_limit = 30_000

pub type Model {
  Model(
    sessions: Sessions,
    session: Session,
    editor: Editor,
    running: Option(Running),
    /// Stepping back through earlier commands, newest is 0. Kept while the
    /// recalled command is unchanged.
    recall: Option(Recall),
    help: Bool,
    /// Dropped files waiting to be placed in the tree.
    mounting: Option(Mounting),
    /// Counts runs, so late messages from an earlier run are ignored.
    runs: Int,
  )
}

pub type Running {
  Running(id: Int, source: e.Expression, worker: Option(process.Pid))
}

/// `upload` is a directory, in the block store, of everything dropped.
pub type Mounting {
  Mounting(upload: v1.Cid, names: List(String), box: combobox.Combobox)
}

pub type Recall {
  Recall(index: Int, shown: projection.Projection)
}

pub type Msg {
  KeyPressed(key: String)
  Pasted(text: String)
  /// Files were dropped and uploaded to the block store.
  Dropped(upload: String)
  WorkerStarted(id: Int, worker: process.Pid)
  Finished(id: Int, output: List(shell.Output), snapshot: shell.Snapshot)
  TimedOut(id: Int)
  SessionChanged(Session)
}

pub fn app() -> lustre.App(#(Sessions, Session), Model, Msg) {
  lustre.application(init, update, view)
}

pub fn new(sessions: Sessions, session: Session) -> Model {
  Model(
    sessions:,
    session:,
    editor: editor.new(),
    running: None,
    recall: None,
    help: False,
    mounting: None,
    runs: 0,
  )
  |> set_editor(editor.new())
}

fn init(args: #(Sessions, Session)) -> #(Model, Effect(Msg)) {
  let #(sessions, session) = args
  #(new(sessions, session), listen(sessions))
}

/// Follow changes made to this session from other tabs.
fn listen(sessions) -> Effect(Msg) {
  use _dispatch, subject <- server_component.select
  sessions.subscribe(sessions, subject)
  process.new_selector()
  |> process.select_map(subject, fn(event) {
    let sessions.Changed(session) = event
    SessionChanged(session)
  })
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    KeyPressed(key) -> key_pressed(model, key)
    Dropped(upload) -> #(dropped(model, upload), effect.none())
    Pasted(text) ->
      case model.running, model.mounting {
        Some(_), _ -> #(model, effect.none())
        None, Some(mounting) -> #(
          Model(
            ..model,
            mounting: Some(
              Mounting(..mounting, box: combobox.paste(mounting.box, text)),
            ),
          ),
          effect.none(),
        )
        None, None -> #(
          set_editor(model, editor.paste(model.editor, text)),
          effect.none(),
        )
      }
    WorkerStarted(id:, worker:) ->
      case model.running {
        Some(running) if running.id == id -> #(
          Model(
            ..model,
            running: Some(Running(..running, worker: Some(worker))),
          ),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    Finished(id:, output:, snapshot:) ->
      case model.running {
        Some(running) if running.id == id ->
          record(model, running.source, output, snapshot)
        _ -> #(model, effect.none())
      }
    TimedOut(id:) ->
      case model.running {
        Some(running) if running.id == id -> {
          stop(running)
          let message =
            "stopped after " <> int.to_string(time_limit / 1000) <> " seconds"
          record(
            model,
            running.source,
            [shell.Failure(message)],
            sessions.current(model.session),
          )
        }
        _ -> #(model, effect.none())
      }
    SessionChanged(session) ->
      case session.id == model.session.id {
        True -> #(Model(..model, session:), effect.none())
        False -> #(model, effect.none())
      }
  }
}

/// Ask where to put the dropped files, offering the existing directories.
fn dropped(model: Model, upload: String) -> Model {
  let store = sessions.store(model.sessions)
  case model.running, v1.from_string(upload) {
    None, Ok(#(upload, _)) ->
      case fs.links(store, upload, "/") {
        Ok(links) -> {
          let root = sessions.current(model.session).root
          let directories =
            fs.directories(store, root)
            |> list.map(fn(directory) { #(directory, "directory") })
          let box =
            combobox.Combobox(
              ..combobox.new(directories, "/"),
              validate: fn(directory) {
                case string.starts_with(directory, "/") {
                  True -> Ok(Nil)
                  False -> Error("Start the directory with /")
                }
              },
            )
          let names = list.map(links, fn(link) { link.name })
          Model(..model, mounting: Some(Mounting(upload, names, box)))
        }
        Error(_) -> model
      }
    _, _ -> model
  }
}

fn mount_key(model: Model, mounting: Mounting, key: String) {
  case combobox.update(mounting.box, key) {
    combobox.Cancelled -> #(Model(..model, mounting: None), effect.none())
    combobox.Updated(box) -> #(
      Model(..model, mounting: Some(Mounting(..mounting, box:))),
      effect.none(),
    )
    combobox.Selected(directory) -> {
      let store = sessions.store(model.sessions)
      let snapshot = sessions.current(model.session)
      let grafted = {
        use links <- result.try(fs.links(store, mounting.upload, "/"))
        fs.graft(store, snapshot.root, directory, links)
      }
      case grafted {
        Ok(root) -> {
          let command = sessions.Mount(directory, mounting.names)
          let snapshot = shell.Snapshot(..snapshot, root:)
          let model = Model(..model, mounting: None)
          record_step(model, command, [], snapshot)
        }
        Error(reason) -> {
          let box = combobox.Combobox(..mounting.box, error: Some(reason))
          #(
            Model(..model, mounting: Some(Mounting(..mounting, box:))),
            effect.none(),
          )
        }
      }
    }
  }
}

fn key_pressed(model: Model, key: String) -> #(Model, Effect(Msg)) {
  case model.mounting {
    Some(mounting) if model.running == None -> mount_key(model, mounting, key)
    _ -> editing_key(model, key)
  }
}

fn editing_key(model: Model, key: String) -> #(Model, Effect(Msg)) {
  case model.running, model.editor.mode, key {
    Some(running), _, "esc" -> {
      stop(running)
      record(
        model,
        running.source,
        [shell.Failure("interrupted")],
        sessions.current(model.session),
      )
    }
    Some(_), _, _ -> #(model, effect.none())
    None, editor.Navigating, "?" -> #(
      Model(..model, help: !model.help),
      effect.none(),
    )
    None, editor.Navigating, "up" | None, editor.Navigating, "down" ->
      recall(model, key)
    None, _, _ -> edit(model, key)
  }
}

fn edit(model: Model, key: String) -> #(Model, Effect(Msg)) {
  case editor.key(model.editor, key) {
    editor.Edited(edited) -> #(set_editor(model, edited), effect.none())
    editor.Run(source) -> run(model, source)
  }
}

/// Type check the draft against the current scope and file system,
/// which also answers its imports.
fn set_editor(model: Model, edited: Editor) -> Model {
  let snapshot = sessions.current(model.session)
  let store = sessions.store(model.sessions)
  let edited = editor.with_files(edited, fs.files(store, snapshot.root))
  let edited =
    editor.check(edited, snapshot.scope, fn(step) {
      modules.drive(step, store, snapshot.root)
    })
  Model(..model, editor: edited, recall: None)
}

/// Up and Down step through earlier commands while the draft is empty or
/// still shows an unchanged earlier command. Otherwise they move the
/// selection.
fn recall(model: Model, key: String) -> #(Model, Effect(Msg)) {
  let commands =
    list.drop(model.session.steps, 1)
    |> list.filter_map(fn(step) {
      case step.command {
        sessions.Code(source) -> Ok(source)
        sessions.Mount(..) -> Error(Nil)
      }
    })
    |> list.reverse
  let next = case model.recall, key {
    Some(Recall(index:, shown:)), _ if shown == model.editor.buffer.projection ->
      case key {
        "up" -> Ok(index + 1)
        _ -> Ok(index - 1)
      }
    _, "up" ->
      case editor.is_empty(model.editor) {
        True -> Ok(0)
        False -> Error(Nil)
      }
    _, _ -> Error(Nil)
  }
  case next {
    Error(Nil) -> edit(model, key)
    Ok(index) if index < 0 -> #(set_editor(model, editor.new()), effect.none())
    Ok(index) ->
      case list.drop(commands, index) {
        [] -> #(model, effect.none())
        [source, ..] -> {
          let model = set_editor(model, editor.from_expression(source))
          let shown = model.editor.buffer.projection
          #(Model(..model, recall: Some(Recall(index, shown))), effect.none())
        }
      }
  }
}

fn run(model: Model, source: e.Expression) -> #(Model, Effect(Msg)) {
  let id = model.runs
  let store = sessions.store(model.sessions)
  let snapshot = sessions.current(model.session)
  let effect = {
    use dispatch <- effect.from
    let worker =
      process.spawn_unlinked(fn() {
        let #(output, snapshot) = shell.run(store, source, snapshot)
        dispatch(Finished(id, output, snapshot))
      })
    dispatch(WorkerStarted(id, worker))
    process.spawn_unlinked(fn() {
      process.sleep(time_limit)
      dispatch(TimedOut(id))
    })
    Nil
  }
  #(
    Model(
      ..model,
      running: Some(Running(id, source, None)),
      runs: id + 1,
      recall: None,
      help: False,
      editor: editor.new(),
    ),
    effect,
  )
}

fn stop(running: Running) -> Nil {
  case running.worker {
    Some(worker) -> process.kill(worker)
    None -> Nil
  }
}

fn record(model: Model, source, output, snapshot) -> #(Model, Effect(Msg)) {
  record_step(model, sessions.Code(source), output, snapshot)
}

fn record_step(model: Model, command, output, snapshot) {
  let step = Step(command, output, snapshot, sessions.now())
  let session = case sessions.append(model.sessions, model.session.id, step) {
    Ok(session) -> session
    Error(Nil) -> model.session
  }
  let model = Model(..model, session:, running: None)
  // The new scope changes the types in the draft.
  let edited =
    editor.Editor(
      ..model.editor,
      buffer: buffer.invalidate(model.editor.buffer),
    )
  #(set_editor(model, edited), effect.none())
}

// VIEW ------------------------------------------------------------------------

pub fn view(model: Model) -> Element(Msg) {
  let session = model.session
  let inherited = case session.origin {
    Some(origin) -> origin.step + 1
    None -> 0
  }
  let steps =
    list.index_map(session.steps, fn(step, index) {
      step_view(session.id, step, index, index < inherited)
    })
  let divider = case session.origin {
    Some(origin) -> [
      html.div([attribute.class("divider")], [
        html.text("forked from "),
        session_link(origin.session),
        html.text(" after " <> plural(origin.step, "command")),
      ]),
    ]
    None -> []
  }
  let #(before, after) = list.split(steps, inherited)
  html.div([attribute.class("terminal")], [
    html.header([attribute.class("terminal-bar")], [
      html.span([attribute.class("terminal-title")], [
        html.text("session " <> session.id),
        ..case session.origin {
          Some(origin) -> [
            html.text(" · fork of "),
            session_link(origin.session),
          ]
          None -> []
        }
      ]),
      html.label([attribute.class("mount-button")], [
        html.text("mount folder"),
        html.input([
          attribute.type_("file"),
          attribute.attribute("webkitdirectory", ""),
          attribute.attribute("multiple", ""),
          attribute.attribute("data-eyg-mount", ""),
        ]),
      ]),
      html.span([attribute.class("terminal-root")], [
        html.text("root "),
        html.code([attribute.title("CID of the file system root")], [
          html.text(v1.to_string(sessions.current(session).root)),
        ]),
      ]),
    ]),
    html.div(
      [
        attribute.class("terminal-scroll"),
        attribute.tabindex(0),
        attribute.autofocus(True),
        attribute.attribute("data-eyg-keys", ""),
        attribute.role("application"),
        attribute.aria_label("EYG shell, press ? for keys"),
        on_key(),
        on_paste(),
        on_drop(),
      ],
      [
        html.pre(
          [attribute.class("terminal-screen")],
          list.flatten([before, divider, after, [current(model)]]),
        ),
      ],
    ),
  ])
}

fn current(model: Model) -> Element(Msg) {
  case model.running {
    Some(running) ->
      html.div([attribute.class("step running")], [
        lines(terminal.code_lines(running.source)),
        lines([dim_line("running… esc to stop")]),
      ])
    None ->
      html.div(
        [attribute.class("step editing")],
        list.flatten([
          case model.mounting {
            Some(mounting) -> [lines(mount_lines(mounting))]
            None -> []
          },
          [lines(draft_lines(model.editor))],
          [lines(dialog_lines(model.editor))],
          [lines([status_line(model.editor)])],
          case model.help {
            True -> [lines(help_lines())]
            False -> []
          },
        ]),
      )
  }
}

fn draft_lines(edited: Editor) -> List(Line) {
  let active = edited.mode == editor.Navigating
  case editor.is_empty(edited) {
    True ->
      terminal.prompted([
        span.line_new([
          span.span_styled(
            " ",
            style.default_style()
              |> style.add_modifier(style.reverse())
              |> style.add_modifier(style.blink()),
          ),
          span.span_styled(
            " press a key to write EYG, ? for help, paste code or drop files",
            terminal.dim_style(),
          ),
        ]),
      ])
    False -> terminal.prompted(code.editing(edited.buffer, active))
  }
}

fn mount_lines(mounting: Mounting) -> List(Line) {
  [
    span.line_new([
      span.span_styled(
        "mount "
          <> string.join(mounting.names, ", ")
          <> " · choose a directory · tab completes · enter to mount · esc to cancel",
        terminal.info_style(),
      ),
    ]),
    ..combobox.lines(mounting.box, 8)
  ]
}

fn dialog_lines(edited: Editor) -> List(Line) {
  let title = fn(text) {
    span.line_new([span.span_styled(text, terminal.info_style())])
  }
  case edited.mode {
    editor.Navigating -> []
    editor.EnterText(editing, _) -> [
      title("text · enter to apply · esc to cancel"),
      combobox.input_line(editing),
    ]
    editor.EnterInteger(editing, _) -> [
      title("integer · enter to apply · esc to cancel"),
      combobox.input_line(editing),
    ]
    editor.EnterCid(editing, _) -> [
      title("content reference · enter to apply · esc to cancel"),
      combobox.input_line(editing),
    ]
    editor.Importing(box, _) -> [
      title(
        "import a file · tab completes · ↑↓ select · enter to apply · esc to cancel",
      ),
      ..combobox.lines(box, 8)
    ]
    editor.Picking(box, _) -> [
      title(
        "choose · tab completes · ↑↓ select · enter to apply · esc to cancel",
      ),
      ..combobox.lines(box, 8)
    ]
  }
}

/// A message, or the type of the selection and the number of type errors.
fn status_line(edited: Editor) -> Line {
  case edited.message {
    Some(message) ->
      span.line_new([span.span_styled("! " <> message, terminal.error_style())])
    None ->
      case editor.is_empty(edited) {
        True -> span.line_plain("")
        False -> {
          let check = case list.length(buffer.block_errors(edited.buffer)) {
            0 ->
              span.span_styled(
                "✔ ",
                style.with_fg(style.default_style(), style.Indexed(2)),
              )
            n ->
              span.span_styled(
                "!" <> int.to_string(n) <> " ",
                terminal.error_style(),
              )
          }
          span.line_new([check, focus_type(edited)])
        }
      }
  }
}

fn focus_type(edited: Editor) {
  case buffer.target_info(edited.buffer) {
    Ok(info) ->
      case info.status {
        Ok(Nil) ->
          span.span_styled(debug.mono(info.type_), terminal.dim_style())
        Error(error.Todo) ->
          span.span_styled(
            "needs " <> debug.mono(info.type_),
            style.with_fg(style.default_style(), style.Indexed(3)),
          )
        Error(reason) ->
          span.span_styled(debug.reason(reason), terminal.error_style())
      }
    Error(Nil) ->
      case buffer.selection_type(edited.buffer) {
        Ok(isomorphic.Var(_)) | Error(_) -> span.span_plain("")
        Ok(type_) -> span.span_styled(debug.mono(type_), terminal.dim_style())
      }
  }
}

fn help_lines() -> List(Line) {
  let width =
    list.fold(editor.bindings, 0, fn(width, binding) {
      int.max(width, string.length(binding.0))
    })
  [
    span.line_new([span.span_styled("keys", terminal.info_style())]),
    ..list.map(editor.bindings, fn(binding) {
      let #(keys, action) = binding
      span.line_new([
        span.span_styled(
          "  " <> string.pad_end(keys, width + 2, " "),
          style.with_fg(style.default_style(), style.Indexed(3)),
        ),
        span.span_plain(action),
      ])
    })
  ]
}

fn dim_line(text) {
  span.line_new([span.span_styled(text, terminal.dim_style())])
}

fn step_view(session_id, step: sessions.Step, index, inherited) {
  let class = case inherited {
    True -> "step inherited"
    False -> "step"
  }
  let fork = fork_button(session_id, index)
  case index {
    0 ->
      html.div([attribute.class(class <> " start")], [
        lines([dim_line("EYG shell, press ? for keys")]),
        fork,
      ])
    _ ->
      html.div([attribute.class(class)], [
        fork,
        lines(terminal.command_lines(step.command)),
        lines(list.flat_map(step.output, terminal.output_lines)),
      ])
  }
}

fn fork_button(session_id, index) {
  html.form(
    [
      attribute.class("fork"),
      attribute.method("post"),
      attribute.action("/sessions/" <> session_id <> "/fork"),
    ],
    [
      html.input([
        attribute.type_("hidden"),
        attribute.name("step"),
        attribute.value(int.to_string(index)),
      ]),
      html.button(
        [
          attribute.type_("submit"),
          attribute.title("Start a new session from this point"),
        ],
        [html.text("fork")],
      ),
    ],
  )
}

fn session_link(id) {
  html.a([attribute.href("/sessions/" <> id)], [html.text(id)])
}

fn plural(n, word) {
  case n {
    1 -> "1 " <> word
    _ -> int.to_string(n) <> " " <> word <> "s"
  }
}

fn lines(lines) {
  element.fragment(term_html.lines(lines))
}

fn on_key() {
  event.on("eyg-key", {
    use key <- decode.subfield(["detail", "key"], decode.string)
    use ctrl <- decode.subfield(["detail", "ctrl"], decode.bool)
    use alt <- decode.subfield(["detail", "alt"], decode.bool)
    use shift <- decode.subfield(["detail", "shift"], decode.bool)
    case key_name(key, ctrl:, alt:, shift:) {
      Ok(name) -> decode.success(KeyPressed(name))
      Error(Nil) -> decode.failure(KeyPressed(""), "unhandled key")
    }
  })
  |> server_component.include([
    "detail.key", "detail.ctrl", "detail.alt", "detail.shift",
  ])
}

fn on_drop() {
  event.on("eyg-drop", {
    use upload <- decode.subfield(["detail", "upload"], decode.string)
    decode.success(Dropped(upload))
  })
  |> server_component.include(["detail.upload"])
}

fn on_paste() {
  event.on("eyg-paste", {
    use text <- decode.field("detail", decode.string)
    decode.success(Pasted(text))
  })
  |> server_component.include(["detail"])
}

/// Name a browser key the way the editor does.
pub fn key_name(
  key: String,
  ctrl ctrl: Bool,
  alt alt: Bool,
  shift shift: Bool,
) -> Result(String, Nil) {
  case key {
    "ArrowUp" -> Ok("up")
    "ArrowDown" -> Ok("down")
    "ArrowLeft" -> Ok("left")
    "ArrowRight" -> Ok("right")
    "Enter" -> Ok("enter")
    "Escape" -> Ok("esc")
    "Backspace" -> Ok("backspace")
    "Delete" -> Ok("delete")
    "Tab" if shift -> Ok("backtab")
    "Tab" -> Ok("tab")
    "Home" -> Ok("home")
    "End" -> Ok("end")
    _ ->
      case string.length(key), ctrl, alt {
        1, True, _ -> Ok("ctrl+" <> string.lowercase(key))
        1, _, True -> Ok("alt+" <> string.lowercase(key))
        1, False, False -> Ok(key)
        _, _, _ -> Error(Nil)
      }
  }
}
