import gleam/dynamic.{Dynamic}
import gleam/io
import gleam/int
import gleam/list
import gleam/map
import gleam/option.{None, Option, Some}
import gleam/string
import gleam_extra
import eyg/typer/monotype as t
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/interpreter
import eyg/interpreter/stepwise
import eyg/editor/editor
import eyg/workspace/server
import eyg/analysis
import eyg/typer
import eyg/codegen/javascript
import platform/browser
import gleam/javascript as real_js

pub external fn to_object(entries: List(#(String, Dynamic))) -> Dynamic =
  "../../eyg_utils.js" "entries_to_object"

pub type Panel {
  OnEditor
  // TODO 0 is tets suite but maybe better with enum, unlees we number mounts
  OnMounts
}

pub type App {
  App(key: String, mount: Mount(Dynamic))
}

pub type Workspace {
  Workspace(
    focus: Panel,
    editor: Option(editor.Editor),
    active_mount: Int,
    apps: List(App),
  )
}

// Numbered workspaces make global things like firmata connection trick can just be named
// Bench rename panel benches?
pub type Mount(a) {
  Static(value: String)
  String2String(
    input: String,
    output: String,
    func: Option(fn(String) -> String),
  )
  TestSuite(result: String)
  UI(
    initial: Option(a),
    state: Option(
      #(
        Dynamic,
        fn(Dynamic) -> Result(Dynamic, String),
        fn(Dynamic) -> Result(Dynamic, String),
      ),
    ),
    rendered: String,
  )
  // State, render handle
  Pure(Option(#(Dynamic, fn(Dynamic) -> String, fn(Dynamic) -> Dynamic, real_js.Reference(List(Action)))))
  Firmata(scan: Option(fn(Dynamic) -> Dynamic))
  Server(handle: Option(fn(Dynamic) -> Dynamic))
  // Only difference between server and universial is that universal works with source
  Universal(handle: Option(fn( String,  String,  String) -> String))
  Interpreted(state: #(real_js.Reference(List(interpreter.Object)), interpreter.Object))
  IServer(handle: fn(String, String, String) -> String)
}

// mount handling of keydown
pub fn handle_keydown(app, k, ctrl, text) {
  let App(key, mount) = app
  // Need an init from first time we focus
  case mount {
    UI(initia, state, rendered) -> {
      io.debug("count all this state")
      app
    }
    Pure(Some(#(state, render, update, ref))) -> {
      let state = update(dynamic.from(#(key, state)))
      io.debug("new state")
      io.debug(state)
      let mount = Pure(Some(#(state, render, update, ref)))
      App(key, mount)
    }
    Interpreted(state) -> {
      let state = stepwise.handle_keydown(state, k)
      let mount = Interpreted(state)
      App(key, mount)
    }
    _ -> app
  }
}

pub fn handle_input(app, data) {
  let App(key, mount) = app

  let mount = case app.mount {
    String2String(input, output, func) ->
      case func {
        None -> String2String(data, output, func)
        Some(f) -> {
          let output = f(data)
          String2String(data, output, func)
        }
      }
    _ -> todo("this app dont change here")
  }
  App(key, mount)
}

pub fn handle_click(app) {
  let App(key, mount) = app

  let mount = case app.mount {
    UI(initial, Some(#(state, update, render)), _) -> {
      assert Ok(state) = update(state)
      assert Ok(rendered) = render(state)
      assert Ok(rendered) = dynamic.string(rendered)
      UI(initial, Some(#(state, update, render)), rendered)
    }
    _ -> todo("this app dont change here")
  }
  App(key, mount)
}

pub fn dispatch_to_app(workspace: Workspace, function) {
  let pre = list.take(workspace.apps, workspace.active_mount)
  assert [app, ..post] = list.drop(workspace.apps, workspace.active_mount)
  let app = function(app)
  let apps = list.append(pre, [app, ..post])
  Workspace(..workspace, apps: apps)
}


pub fn mount_constraint(mount) {
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
    String2String(_, _, _) -> t.Function(t.Binary, t.Binary)
    UI(_, _, _) ->
      t.Record(
        [
          #("init", t.Function(t.Tuple([]), t.Unbound(-2))),
          #("update", t.Function(t.Unbound(-2), t.Unbound(-2))),
          #("render", t.Function(t.Unbound(-2), t.Binary)),
        ],
        None,
      )
    Pure(_) -> t.Record([
      #("render", t.Function(t.Unbound(-4), t.Binary)),
      #("init", t.Function(t.Record([
          #("on_keypress",t.Function(
            // t.Tuple([t.Binary, t.Unbound(-4)]), t.Function(t.Tuple([]), t.Unbound(-4))
            // handler
            t.Function(t.Tuple([t.Binary, t.Unbound(-4)]), t.Unbound(-4)),
            // continuation
            t.Function(t.Function(t.Tuple([]), t.Unbound(-5)), t.Unbound(-5))
          ))
        ], None)
      , t.Unbound(-4)))
      ], None)
    Firmata(_) -> {
      // TODO move boolean to standard types
      let boolean =
        t.Union([#("True", t.Tuple([])), #("False", t.Tuple([]))], None)
      let input = t.Record([], None)
      let state = t.Unbound(-2)
      let output = t.Record([#("Pin12", boolean), #("Pin13", boolean)], None)
      t.Function(t.Tuple([input, state]), t.Tuple([output, state]))
    }
    Server(_) -> t.Function(t.Binary, t.Binary)
    Universal(_) -> t.Function(
      t.Record([#("Method", t.Binary), #("Path", t.Binary), #("Body", t.Binary)], None), 
      t.Function(
        t.Record([
          #("OnKeypress", t.Function(t.Function(t.Binary, t.Tuple([])), t.Tuple([]))), 
          #("render", t.Function(t.Binary, t.Tuple([]))),  
          #("log", t.Function(t.Binary, t.Tuple([]))),
          #("send", t.Function(t.Tuple([t.Native("Address", [t.Unbound(-3)]), t.Unbound(-3)]), t.Tuple([]))),
          ], None), 
        t.Binary
      )
    )
    Static(_) -> t.Unbound(-2)
    Interpreted(_) -> t.Function(t.Record([
      #("ui", t.Native("Pid", [t.Binary])),
      #("on_keypress", t.Native("Pid", [t.Function(t.Binary, t.Tuple([]))])),
      #("fetch", t.Native("Pid", [t.Tuple([t.Binary, t.Function(t.Binary, t.Tuple([]))])])),
      ], None), t.Tuple([])) 
    IServer(_) -> t.Function(
      t.Record([#("method", t.Binary), #("path", t.Binary), #("body", t.Binary)], None), 
      t.Binary
    )
  }
}

pub fn app_constraint(app) {
  let App(key, mount) = app
  let constraint = t.Record([#(key, mount_constraint(mount))], Some(-1))
}

pub fn focus_on_mount(before: Workspace, index) {
  assert Ok(app) = list.at(before.apps, index)
  let constraint = app_constraint(app)
  let editor = case before.editor {
    None -> None
    Some(editor) -> {
      let editor = editor.set_constraint(editor, constraint)
      Some(editor)
    }
  }

  let workspace =
    Workspace(..before, focus: OnMounts, active_mount: index, editor: editor)
  case workspace.editor {
    Some(editor.Editor(cache: editor.Cache(evaled: Ok(code), ..), source: s ..)) -> {
      let func = code_update(code, s, _)
      dispatch_to_app(workspace, func)
    }
    _ -> workspace
  }
}

pub type Action {
  Keypress(fn(Dynamic) -> Dynamic)
}


pub fn code_update(code, source, app) {
  let App(key, mount) = app
  io.debug("running the app")
  let mount = case mount {
    Interpreted(old) -> {
      case stepwise.run_browser(e.access(source, key)) {
        Ok(new) -> Interpreted(new) 
        Error(reason) -> {
          io.debug("failed to interpret")
          io.debug(reason)
          Interpreted(old)
        }
      }
    }
    IServer(old) -> {
      case server.boot(e.access(source, key)) {
        Ok(new) -> IServer(new) 
        Error(reason) -> {
          io.debug("failed to interpret")
          io.debug(reason)
          IServer(old)
        }
      }
    }
    TestSuite(_) -> {
      let cast = gleam_extra.dynamic_function
      assert Ok(prog) = dynamic.field(key, cast)(code)
      assert Ok(r) = prog(dynamic.from([]))
      |> io.debug()
      // TODO Inner value should be tuple 0, probably should be added to gleam extra
      case dynamic.field("True", Ok)(r) {
        Ok(inner) -> TestSuite("True")
        Error(_) -> TestSuite("False")
      }
    }
    String2String(input, output, _) -> {
      let cast = gleam_extra.dynamic_function
      assert Ok(prog) = dynamic.field(key, cast)(code)
      let prog = fn(input: String) {
        assert Ok(output) = prog(dynamic.from(input))
        assert Ok(output) = dynamic.string(output)
        output
      }
      let output = prog(input)
      String2String(input, output, Some(prog))
    }
    Firmata(_) -> {
      let cast = gleam_extra.dynamic_function
      assert Ok(scan) = dynamic.field(key, cast)(code)
      Firmata(Some(fn(x) {
        assert Ok(returned) = scan(x)
        returned
      }))
    }
    UI(initial, state, rendered) -> {
      assert Ok(record) = dynamic.field(key, Ok)(code)
      let cast = gleam_extra.dynamic_function
      assert Ok(init) = dynamic.field("init", cast)(record)
      assert Ok(update) = dynamic.field("update", cast)(record)
      assert Ok(render) = dynamic.field("render", cast)(record)
      assert Ok(new_initial) = init(dynamic.from([]))
      case Some(new_initial) == initial {
        False -> {
          let initial = new_initial
          let state = new_initial
          assert Ok(rendered) = render(state)
          assert Ok(rendered) = dynamic.string(rendered)
          UI(Some(new_initial), Some(#(state, update, render)), rendered)
        }
        True -> {
          assert Some(#(state, _update, _render)) = state
          assert Ok(rendered) = render(state)
          let state = Some(#(state, update, render))
          assert Ok(rendered) = dynamic.string(rendered)
          UI(initial, state, rendered)
        }
      }
    }
    // TODO actually update
    Pure(_) -> {
      assert Ok(record) = dynamic.field(key, Ok)(code)
      let cast = gleam_extra.dynamic_function
      assert Ok(init) = dynamic.field("init", cast)(record)
      assert Ok(render) = dynamic.field("render", cast)(record)
      let ref = real_js.make_reference([])
      let env = to_object([
        #("on_keypress", dynamic.from(fn(handle) { 
          real_js.update_reference(ref, fn(x) {[handle, ..x]})
          // io.debug(handle)
          // io.debug(handle(["key A", "state"]))
          // io.debug("TODO register handle")
          // How do we get out the values from pure in here
          // This pulls the handle out for continuation
          // Probably some linked list unwrapping needed here.
          fn(cont) {cont([])}
        }))
      ])

      assert Ok(new_initial) = init(env)
      |> io.debug()
      io.debug("that was the result")
      // assert Ok(#(handle, initial)) = dynamic.tuple2(gleam_extra.dynamic_function, Ok)(new_initial)
      // io.debug(initial)
      let render = fn(state) {
        assert Ok(rendered) = render(state)
        assert Ok(rendered) = dynamic.string(rendered)
        rendered
      }
      let [Keypress(handle),] = real_js.dereference(ref)
      // let handle = fn(x) {
      //   assert Ok(state) = handle(x) 
      //   state
      // }
      Pure(Some(#(new_initial, render, handle, ref)))
    }
    Static(_) -> todo("probably remove I don't see much value in static")
    Server(_) -> {
      let cast = gleam_extra.dynamic_function
      assert Ok(handle) = dynamic.field(key, cast)(code)
      Server(Some(fn(x) {
        assert Ok(returned) = handle(x)
        returned
      }))
    }
    Universal(_) -> {
      // TODO this looses scope but issues with rewritting harness
      // Need to shake tree
      // assert #(_, e.Record(fields)) = last_term(source)
      // assert Ok(server_source) = list.key_find(fields, key) 
      let server_source = e.access(source, key)

      // rerender as a function same as capture
      // Pass in dom arguments
      // on click at all times
      // Need mutable ref or app state

      let #(typed, typer) = analysis.infer(server_source, t.Unbound(-1), [], )
      let #(typed, typer) = typer.expand_providers(typed, typer, [])

      let top_env = map.new()
      |> map.insert("harness", interpreter.Record([
        #("compile", interpreter.Function(p.Variable(""), e.tagged("Error", e.binary("not in interpreter")), map.new(), None)), 
        #("debug", interpreter.BuiltinFn(io.debug)),
        #("spawn", interpreter.BuiltinFn(interpreter.spawn))
      ]))

      let #(server_fn, coroutines) = interpreter.run(editor.untype(typed), top_env, [])

      let handler = fn (method, path, body) { 
        case method, string.split(path, "/") {
          "POST", ["", "_", id] -> {
            assert Ok(pid) = int.parse(id)
            assert Ok(c) = list.at(coroutines, pid)
            interpreter.exec_call(c, interpreter.Binary(body))
            ""
          }
          _,_ -> {

   
// We expand the providers but the exec needs dynamic
        let server_arg = interpreter.Record([#("Method", interpreter.Binary(method)),#("Path", interpreter.Binary(path)),#("Body", interpreter.Binary(body))])

        
        // client function
        assert interpreter.Function(pattern, body, captured, _) = interpreter.exec_call(server_fn, server_arg)

        let client_source = e.function(pattern, body)
        
        // TODO captured should not include empty
        let #(typed, typer) = analysis.infer(client_source, t.Unbound(-1), [], )
        let #(typed, typer) = typer.expand_providers(typed, typer, [])

        let program = list.map(map.to_list(captured), interpreter.render_var)
        |> list.append([javascript.render_to_string(typed, typer)])
        |> string.join("\n")
        |> string.append("({
OnKeypress: (f) => document.addEventListener(\"keydown\", function (event) {
    f(event.key);
  }),
render: (value) => document.body.innerHTML = value,
log: (x) => console.log(x),
send: ([pid, message]) => {
  fetch(`${window.location.pathname}/_/${pid}`, {method: 'POST', body: message})
}
});")
string.concat(["<head></head><body></body><script>", program, "</script>"])
      }
             }
        }
      Universal(Some(handler))
    }
  }
  App(key, mount)
}

// TODO REPL in place in tree as app

fn last_term(source) { 
  let #(_, tree) = source
  case tree {
    e.Let(_,_, then) -> last_term(then) 
    _ -> source
  }
 }

// CLI
// ScanCycle
// TODO add inspect to std lib
external fn inspect_gleam(a) -> String =
  "../../gleam" "inspect"

external fn inspect(a) -> String =
  "" "JSON.stringify"
