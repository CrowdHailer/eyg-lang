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
import eyg/editor/ui as editor_ui
import platform/browser
import eyg/workspace/workspace.{OnEditor, OnMounts, Workspace}

external fn fetch(String) -> Promise(String) =
  "../../browser_ffi" "fetchSource"

// TODO move to workspace
pub fn init() {
  let state =
    Workspace(
      focus: OnEditor,
      editor: None,
      active_mount: 0,
      apps: [
        workspace.App("counter", workspace.UI(None, None, "")),
        workspace.App("test", workspace.TestSuite("True")),
        workspace.App("cli", workspace.String2String("", "")),
        workspace.App("scan", workspace.Firmata(None)),
      ],
    )

  let task =
    promise.map(
      fetch("./saved.json"),
      fn(data) {
        fn(before) {
          let e = editor.init(data, browser.harness())
          let state = Workspace(..before, editor: Some(e))
          let state = workspace.focus_on_mount(state, 0)

          #(state, array.from_list([]))
        }
      },
    )
  #(state, array.from_list([task]))
}

pub type Transform(n) =
  fn(Workspace(n)) ->
    #(Workspace(n), Array(Promise(fn(Workspace(n)) -> #(Workspace(n), Nil))))

pub fn click(marker) -> Transform(n) {
  fn(before: Workspace(n)) {
    let state = case marker {
      ["editor", ..rest] -> {
        let editor = case list.reverse(rest), before.editor {
          [], _ -> before
          [last, ..], Some(editor) -> {
            let editor = editor_ui.handle_click(editor, last)
            let workspace =
              Workspace(..before, focus: OnEditor, editor: Some(editor))
            case editor.eval(editor) {
              Ok(code) -> {
                let func = workspace.code_update(code, _)
                workspace.dispatch_to_app(workspace, func)
              }
              _ -> workspace
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
pub fn keydown(key: String, ctrl: Bool, text: Option(String)) -> Transform(n) {
  handle_keydown(_, key, ctrl, text)
}

fn handle_keydown(before, key: String, ctrl: Bool, text: Option(String)) {
  let state = case before {
    Workspace(focus: OnEditor, editor: Some(editor), ..) -> {
      let editor = editor_ui.handle_keydown(editor, key, ctrl, text)
      let workspace = Workspace(..before, editor: Some(editor))
      case editor.eval(editor) {
        Ok(code) -> {
          let func = workspace.code_update(code, _)
          workspace.dispatch_to_app(workspace, func)
        }
        _ -> workspace
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

pub fn on_input(data, marker) -> Transform(n) {
  fn(before) {
    let workspace = case before {
      Workspace(focus: OnMounts, editor: Some(editor), active_mount: i, ..) ->
        case editor.eval(editor) {
          Ok(code) -> {
            let func = workspace.handle_input(_, data)
            workspace.dispatch_to_app(before, func)
          }
          _ -> before
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
pub fn editor_focused(state: Workspace(n)) {
  state.focus == OnEditor
}

pub fn bench_focused(state: Workspace(n)) {
  case state.focus {
    OnMounts -> True
    _ -> False
  }
}

pub fn get_editor(state: Workspace(n)) {
  case state.editor {
    None -> dynamic.from(Nil)
    Some(editor) -> dynamic.from(editor)
  }
}

pub fn benches(workspace: Workspace(_)) {
  workspace.apps
  |> array.from_list()
}

// Not needed I don;t think
pub fn is_active(state: Workspace(_), index) {
  case state {
    Workspace(focus: OnMounts, active_mount: a, ..) if a == index -> True
    _ -> False
  }
}

pub fn running_app(state: Workspace(_)) {
  case state {
    Workspace(apps: apps, active_mount: a, ..) ->
      case list.at(apps, a) {
        Error(_) -> dynamic.from(Nil)
        Ok(app) -> dynamic.from(app)
      }
    _ -> dynamic.from(Nil)
  }
}
