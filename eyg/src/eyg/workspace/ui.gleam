import gleam/dynamic.{Dynamic}
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleam/option.{None, Option, Some}
import gleam_extra
import gleam/javascript/array.{Array}
import gleam/javascript/promise.{Promise}
import eyg/editor/editor
import eyg/ast/encode
import eyg/editor/ui as editor_ui
import platform/browser
import eyg/ast/expression as e
import eyg/interpreter/interpreter as r
import eyg/interpreter/stepwise
import eyg/workspace/workspace.{OnEditor, OnMounts, Workspace}
import gleam/javascript as real_js

external fn fetch(String) -> Promise(String) =
  "../../browser_ffi" "fetchSource"

fn apps() {
  [
    workspace.App("proxy", workspace.Proxy(Error("No code given"))),
    workspace.App("recipe", workspace.Proxy(Error("No code given"))),
    workspace.App("counter", workspace.UI(None, None, "")),
    workspace.App("fetch", workspace.Pure(None)),
    workspace.App("test", workspace.TestSuite("True")),
    workspace.App("cli", workspace.String2String("", "", None)),
    workspace.App("scan", workspace.Firmata(None)),
    workspace.App("server", workspace.Server(None)),
  ]
}

pub fn deploy(hash) {
  assert Ok(app) = list.find(apps(), fn(app: workspace.App) { app.key == hash })
  promise.map(
    fetch("./saved.json"),
    fn(source) {
      let source = encode.from_json(encode.json_from_string(source))
      let constraint = workspace.app_constraint(app)
      assert editor.Cache(_, _, _, Ok(code)) =
        editor.analyse(source, constraint, browser.harness())
      assert Ok(inner) = dynamic.field(app.key, Ok)(code)
      inner
    },
  )
}

// TODO move to workspace maybe
pub fn init() {
  let state =
    Workspace(focus: OnEditor, editor: None, active_mount: 0, apps: apps())

  let task =
    promise.map(
      fetch("./saved.json"),
      fn(data) {
        fn(before) {
          let e = editor.init(data, browser.harness())
          let workspace = Workspace(..before, editor: Some(e))
          let workspace = workspace.focus_on_mount(workspace, 0)
          #(workspace, array.from_list([]))
        }
      },
    )
  #(state, array.from_list([task]))
}

pub type Transform =
  fn(Workspace) ->
    #(Workspace, Array(Promise(fn(Workspace) -> #(Workspace, Nil))))

pub fn click(marker) -> Transform {
  fn(before: Workspace) {
    let state = case marker {
      ["editor", ..rest] -> {
        let editor = case list.reverse(rest), before.editor {
          [], _ -> before
          [last, ..], Some(before_editor) -> {
            let editor = editor_ui.handle_click(before_editor, last)
            let workspace =
              Workspace(..before, focus: OnEditor, editor: Some(editor))
            let changed = editor.source != before_editor.source
            case changed, editor.cache.evaled {
              True, Ok(code) -> {
                let func = workspace.code_update(code, editor.source, _)
                workspace.dispatch_to_app(workspace, func)
              }
              _, _ -> workspace
            }
          }
        }
      }
      ["bench", ..rest] ->
        case rest {
          [] -> Workspace(..before, focus: OnMounts)
          [mount, ..inner] ->
            case string.split(mount, "mount:") {
              ["", index] -> {
                assert Ok(index) = int.parse(index)
                workspace.focus_on_mount(before, index)
              }
              _ -> {
                let func = workspace.handle_click(_)
                workspace.dispatch_to_app(before, func)
              }
            }
        }
      _ -> before
    }
    #(state, array.from_list([]))
  }
}

// call all the benches Bench with name etc then plus Mount in the middle
pub fn keydown(key: String, ctrl: Bool, text: Option(String)) -> Transform {
  handle_keydown(_, key, ctrl, text)
}

fn handle_keydown(before, key: String, ctrl: Bool, text: Option(String)) {
  let state = case before {
    Workspace(focus: OnEditor, editor: Some(before_editor), ..) -> {
      let editor = editor_ui.handle_keydown(before_editor, key, ctrl, text)
      let workspace = Workspace(..before, editor: Some(editor))
      let changed = editor.source != before_editor.source
      case changed, editor.cache.evaled {
        True, Ok(code) -> {
          let func = workspace.code_update(code, editor.source, _)
          // app gets source
          io.debug("to interpret here")
          workspace.dispatch_to_app(workspace, func)
        }
        _, _ -> workspace
      }
    }
    Workspace(focus: OnMounts, active_mount: i, ..) -> {
      let func = workspace.handle_keydown(_, key, ctrl, text)
      workspace.dispatch_to_app(before, func)
    }
    _ -> before
  }
  #(state, array.from_list([]))
}

pub fn on_input(data, marker) -> Transform {
  fn(before) {
    let workspace = case before {
      Workspace(focus: OnMounts, editor: Some(editor), active_mount: i, ..) -> {
        let func = workspace.handle_input(_, data)
        workspace.dispatch_to_app(before, func)
      }
      Workspace(focus: OnEditor, editor: Some(editor), ..) -> {
        let editor = editor_ui.handle_input(editor, data)
        let workspace = Workspace(..before, editor: Some(editor))
      }
    }
    // This doesn't change the code
    #(workspace, array.from_list([]))
  }
}

// views
pub fn editor_focused(state: Workspace) {
  state.focus == OnEditor
}

pub fn bench_focused(state: Workspace) {
  case state.focus {
    OnMounts -> True
    _ -> False
  }
}

pub fn get_editor(state: Workspace) {
  case state.editor {
    None -> dynamic.from(Nil)
    Some(editor) -> dynamic.from(editor)
  }
}

pub fn benches(workspace: Workspace) {
  workspace.apps
  |> array.from_list()
}

// Not needed I don;t think
pub fn is_active(state: Workspace, index) {
  case state {
    Workspace(focus: OnMounts, active_mount: a, ..) if a == index -> True
    _ -> False
  }
}

pub fn running_app(state: Workspace) {
  case state {
    Workspace(apps: apps, active_mount: a, ..) ->
      case list.at(apps, a) {
        Error(_) -> dynamic.from(Nil)
        Ok(app) -> dynamic.from(app)
      }
    _ -> dynamic.from(Nil)
  }
}
