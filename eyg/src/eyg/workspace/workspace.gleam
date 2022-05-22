import gleam/dynamic
import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import eyg/typer/monotype as t
import eyg/ast/editor

pub type Panel {
  OnEditor
  // TODO 0 is tets suite but maybe better with enum, unlees we number mounts
  OnMounts
}

pub type App {
  App(key: String, mount: Mount)
}

pub type Workspace(n) {
  Workspace(
    focus: Panel,
    editor: Option(editor.Editor(n)),
    active_mount: Int,
    apps: List(App),
  )
}

// Numbered workspaces make global things like firmata connection trick can just be named
// Bench rename panel benches?
pub type Mount {
  Static(value: String)
  String2String
  TestSuite(result: String)
  UI
}

fn mount_constraint(mount) {
  case mount {
    TestSuite(_) ->
      t.Function(
        t.Tuple([]),
        t.Union(
          variants: [#("True", t.Tuple([])), #("False", t.Tuple([]))],
          extra: None,
        ),
      )
    _ -> t.Unbound(-2)
  }
}

pub fn focus_on_mount(before: Workspace(_), index) {
  assert Ok(App(key, mount)) = list.at(before.apps, index)
  let constraint = t.Record([#(key, mount_constraint(mount))], Some(-1))
  let editor = case before.editor {
    None -> None
    Some(editor) -> {
      let editor = editor.set_constraint(editor, constraint)
      Some(editor)
    }
  }
  Workspace(..before, focus: OnMounts, active_mount: index, editor: editor)
}

// CLI
// ScanCycle
// TODO add inspect to std lib
external fn inspect_gleam(a) -> String =
  "../../gleam" "inspect"

external fn inspect(a) -> String =
  "" "JSON.stringify"
