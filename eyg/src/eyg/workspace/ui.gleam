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
import eyg/editor/editor
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
        workspace.App("test", workspace.TestSuite("True")),
        workspace.App("cli", workspace.String2String("", "")),
        workspace.App("scan", workspace.Firmata(None)),
        workspace.App("counter", workspace.UI),
      ],
    )

  let task =
    promise.map(
      fetch("./saved.json"),
      fn(data) {
        fn(before) {
          let e = editor.init(data, browser.harness())
          // TODO take all the constrints first or just active mount
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
        let pre = list.take(before.apps, before.active_mount)
        assert [app, ..post] = list.drop(before.apps, before.active_mount)
        // TODO EDITOR State vs Generated/Compiled might be a way to group the manipulation
        case editor.eval(editor) {
          Ok(code) -> {
            let app = workspace.run_app(code, app)
            let apps = list.append(pre, [app, ..post])
            Workspace(..workspace, apps: apps)
          }
          // todo
          _ -> workspace
        }
      }
      Workspace(focus: OnMounts, active_mount: i, ..) -> {
        let pre = list.take(before.apps, before.active_mount)
        assert [app, ..post] = list.drop(before.apps, before.active_mount)
        // TODO do nothing for now BECAUSE we use on change
        before
      }
      _ -> before
    }
    #(state, array.from_list([]))
  }
}

pub fn on_input(data, marker) -> Transform(n) {
  fn(before) {
    let workspace = case before {
      Workspace(focus: OnMounts, editor: Some(editor), active_mount: i, ..) -> {
        let pre = list.take(before.apps, before.active_mount)
        assert [app, ..post] = list.drop(before.apps, before.active_mount)
        case app.mount {
          workspace.String2String(input, output) -> {
            let mount = workspace.String2String(data, output)
            let app = workspace.App(app.key, mount)
            case editor.eval(editor) {
              Ok(code) -> {
                let app = workspace.run_app(code, app)
                let apps = list.append(pre, [app, ..post])
                Workspace(..before, apps: apps)
              }
              _ -> before
            }
          }
          _ -> todo("this app dont change here")
        }
      }
      _ -> before
    }
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
