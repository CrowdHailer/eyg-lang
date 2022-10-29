import gleam/io
import gleam/list
import gleam/map
import gleam/string
import eyg/interpreter/interpreter as r
import eyg/interpreter/tail_call
// TODO remove and have a compile client function
// has arbitrary effect types as something that composes and we have a big browser harness
import eyg/ast/expression as e
import eyg/analysis
import eyg/typer
import eyg/typer/monotype as t
import eyg/editor/editor
import eyg/codegen/javascript
import eyg/codegen/javascript/runtime
import eyg/interpreter/builtin
import eyg/analysis/shake

fn impl(handler, computation) {
  Ok(r.BuiltinFn(fn(arg) {
    try r = tail_call.eval_call(computation, arg)
    let arg = case r {
      r.Effect(name, value, cont) ->
        r.Tagged(name, r.Tuple([value, r.BuiltinFn(cont)]))
      term -> r.Tagged("Return", term)
    }
    tail_call.eval_call(handler, arg)
  }))
}

fn do(effect) {
  case effect {
    r.Tagged(name, value) -> Ok(r.Effect(name, value, fn(x) { Ok(x) }))
    _ -> Error("not a good effect")
  }
}

external fn log(a) -> Nil =
  "" "console.log"

// TODO this is the one that we are using in latest
fn term_serialize(term) {
  let program =
    string.append("window.Program = ", runtime.render_object(term))
//     |> string.append(
//       "({
//   on_click: (f) => { document.onclick = () => f() },
//   display: (value) => document.body.innerHTML = value,
// });",
//     )
  let page =
    string.concat(["<script>", program, "</script><body></body>"])
  // assert r.Function() = term
  Ok(r.Binary(page))
}

pub fn env() {
  map.new()
  |> map.insert("do", r.BuiltinFn(do))
  |> map.insert(
    "impl",
    r.BuiltinFn(fn(handler) { Ok(r.BuiltinFn(impl(handler, _))) }),
  )
  // Is this part of effectful
  // interpreter/builtins might be better
  // Maybe these should just be fast lookups for certain hashes
  |> map.insert("equal", r.BuiltinFn(r.equal))
  // TODO add types to builtin
  |> map.insert(
    "builtin",
    r.Record([#("serialize", r.BuiltinFn(term_serialize)), ..builtin.builtin()]),
  )
}

pub fn eval(source) {
  tail_call.eval(source, env())
}

pub fn eval_call(func, arg, outbound) {
  try step = tail_call.eval_call(func, arg)
  case step {
    r.Effect(effect, value, cont) -> outbound(effect, value, cont)
    step -> Ok(step)
  }
}

// node fetch probably need node ffi library
// This is not node fetch while we are running in proxy
external fn fetch(String) -> String =
  "" "fetch"

pub fn real_log(effect, value, cont) {
  case effect {
    "Log" -> {
      io.debug(value)
      cont(r.Tuple([]))
    }
    "HTTP" -> {
      io.debug(value)
      assert r.Tagged("Get", r.Binary(url)) = value
      let response =
        r.Binary(fetch(url))
        |> io.debug
      Ok(response)
    }
    _ -> Error(string.concat(["unkown effect ", effect]))
  }
}
