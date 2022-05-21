import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleam/option.{None, Some}
import gleam/javascript/array.{Array}
import gleam/javascript/promise.{Promise}
import eyg/ast/editor
import platform/browser
import eyg/workspace/workspace.{OnEditor, OnMounts, Workspace}

external fn fetch(String) -> Promise(String) =
  "../../browser_ffi" "fetchSource"

// TODO move to workspace
pub fn init() {
  let state = Workspace(focus: OnEditor, editor: None, active_mount: 0)

  let task =
    promise.map(
      fetch("./saved.json"),
      fn(data) {
        fn(before) {
          let e = editor.init(data, browser.harness())
          let state = Workspace(..before, editor: Some(e))

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
          [], _ -> before.editor
          [last, ..], Some(editor) -> Some(editor.handle_click(editor, last))
        }
        Workspace(..before, focus: OnEditor, editor: editor)
      }
      ["bench", ..rest] ->
        case rest {
          [] -> Workspace(..before, focus: OnMounts)
          [mount, ..inner] -> {
            let ["", index] = string.split(mount, "mount:")
            assert Ok(index) =
              index
              |> int.parse()
            Workspace(..before, focus: OnMounts)
          }
        }
      _ -> before
    }
    #(state, array.from_list([]))
  }
}

pub fn keydown(key: String, ctrl: Bool, text: String) -> Transform(n) {
  fn(before) {
    let state = case before {
      Workspace(focus: OnEditor, editor: Some(editor), ..) -> {
        let editor = editor.handle_keydown(editor, key, ctrl, text)
        Workspace(..before, editor: Some(editor))
      }
      _ -> before
    }
    #(state, array.from_list([]))
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

pub fn benches(workspace) {
  workspace.mounts(workspace)
}
