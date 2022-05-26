import gleam/dynamic.{Dynamic}
import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import gleam_extra
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
  String2String(input: String, output: String)
  TestSuite(result: String)
  UI
  Firmata(scan: Option(fn(Dynamic)-> Dynamic))
}

fn mount_constraint(mount) {
  case mount {
    TestSuite(_) ->
      t.Function(
        t.Tuple([]),
        t.Union(
          // TODO t.Bool 
          variants: [#("True", t.Tuple([])), #("False", t.Tuple([]))],
          extra: None,
        ),
      )
    String2String(_, _) -> t.Function(t.Binary, t.Binary)
    UI -> t.Function(t.Unbound(-2), t.Binary)
    Firmata(_) -> {
      // TODO move boolean to standard types
      let boolean = t.Union([#("True", t.Tuple([])),#("False", t.Tuple([]))], None)
      let input = t.Record([], None)
      let state = t.Unbound(-2)
      let output = t.Record([#("Pin12", boolean), #("Pin13", boolean)], None)
      t.Function(t.Tuple([input, state]), t.Tuple([output, state]))
      }
    _ -> t.Unbound(-2)
    
  }
}

fn app_constraint(app) {
  let App(key, mount) = app
  let constraint = t.Record([#(key, mount_constraint(mount))], Some(-1))
}

pub fn focus_on_mount(before: Workspace(_), index) {
  assert Ok(app) = list.at(before.apps, index)
  let constraint = app_constraint(app)
  let editor = case before.editor {
    None -> None
    Some(editor) -> {
      let editor = editor.set_constraint(editor, constraint)
      Some(editor)
    }
  }
  Workspace(..before, focus: OnMounts, active_mount: index, editor: editor)
}

pub fn run_app(code, app) {
  let App(key, mount) = app
  io.debug("running the app")
  let mount = case mount {
    TestSuite(_) -> {
      let cast = gleam_extra.dynamic_function
      assert Ok(prog) = dynamic.field(key, cast)(code)
      assert Ok(r) = prog(dynamic.from([]))
      // TODO Inner value should be tuple 0, probably should be added to gleam extra
      case dynamic.field("True", Ok)(r) {
        Ok(inner) -> TestSuite("True")
        Error(_) -> TestSuite("False")
      }
    }
    String2String(input, output) -> {
      let cast = gleam_extra.dynamic_function
      assert Ok(prog) = dynamic.field(key, cast)(code)
      assert Ok(r) = prog(dynamic.from(input))
      // TODO Inner value should be tuple 0, probably should be added to gleam extra
      case dynamic.string(r) {
        Ok(output) -> {
          io.debug(input)
          io.debug(output)
          String2String(input, output)
        }
        Error(_) -> todo("should always be a string")
      }
    }
    Firmata(_) -> {
      let cast = gleam_extra.dynamic_function
      assert Ok(scan) = dynamic.field(key, cast)(code)
      
      Firmata(Some(fn(x){
        assert Ok(returned) = scan(x)
        returned
      }))
    }
    UI() -> todo("The UI thing")
    Static(_) -> todo("probably remove I don't see much value in static")
  }
  App(key, mount)
}

// CLI
// ScanCycle
// TODO add inspect to std lib
external fn inspect_gleam(a) -> String =
  "../../gleam" "inspect"

external fn inspect(a) -> String =
  "" "JSON.stringify"
