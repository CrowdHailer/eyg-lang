import gleam/dynamic.{Dynamic}
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleam/option.{None, Some}
import gleam_extra
import gleam/javascript/array.{Array}
import gleam/javascript/promise.{Promise}
import eyg/ast/editor
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
      apps: [workspace.App("test", workspace.TestSuite("True"))],
    )

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
          [], _ -> before
          [last, ..], Some(editor) -> {
            let editor = editor.handle_click(editor, last)
            // TODO handle code
            Workspace(..before, focus: OnEditor, editor: Some(editor))
          }
        }
      }
      ["bench", ..rest] ->
        case rest {
          [] -> Workspace(..before, focus: OnMounts)
          [mount, ..inner] -> {
            let ["", index] = string.split(mount, "mount:")
            assert Ok(index) = int.parse(index)
            workspace.focus_on_mount(before, index)
          }
        }
      _ -> before
    }
    #(state, array.from_list([]))
  }
}

// call all the benches Bench with name etc then plus Mount in the middle
// TO
pub fn keydown(key: String, ctrl: Bool, text: String) -> Transform(n) {
  fn(before) {
    let state = case before {
      Workspace(focus: OnEditor, editor: Some(editor), ..) -> {
        let editor = editor.handle_keydown(editor, key, ctrl, text)
        let workspace = Workspace(..before, editor: Some(editor))
        assert Ok(workspace.App(key, mount)) =
          list.at(before.apps, before.active_mount)
        // TODO keep pre an post mount lists in place
        // let evaled = 
        // TODO EDITOR State vs Generated/Compiled might be a way to group the manipulation
        case editor.eval(editor) {
          Ok(code) -> {
            let apps = case dynamic.field(key, gleam_extra.dynamic_function)(
              code,
            ) {
              Ok(test) -> {
                assert Ok(r) = test(dynamic.from([]))
                // TODO Inner value should be tuple 0, probably should be added to gleam extra
                case dynamic.field("True", Ok)(r) {
                  Ok(inner) -> [workspace.App(key, workspace.TestSuite("True"))]
                  Error(_) -> [workspace.App(key, workspace.TestSuite("False"))]
                }
              }
              Error(_) -> [workspace.App(key, mount)]
            }
            Workspace(..workspace, apps: apps)
          }
          // todo
          _ -> workspace
        }
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

pub fn benches(workspace: Workspace(_)) {
  workspace.apps
  |> array.from_list()
}
