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

// TODO move somewhere for interpreter
fn string_append(args) {
  case args {
    r.Tuple([r.Binary(first), r.Binary(second)]) ->
      Ok(r.Binary(string.append(first, second)))
    _ -> {
      io.debug(args)
      Error("bad arguments!!")
    }
  }
}

fn string_uppercase(arg) {
  case arg {
    r.Binary(value) -> Ok(r.Binary(string.uppercase(value)))
    _ -> Error("bad arguments")
  }
}

fn string_lowercase(arg) {
  case arg {
    r.Binary(value) -> Ok(r.Binary(string.lowercase(value)))
    _ -> Error("bad arguments")
  }
}

fn string_replace(arg) {
  case arg {
    r.Tuple([r.Binary(string), r.Binary(target), r.Binary(replacement)]) ->
      Ok(r.Binary(string.replace(string, target, replacement)))
    _ -> Error("bad arguments")
  }
}

fn term_serialize(term) {
  // io.debug(term)
  assert r.Function(pattern, body, captured, _) = term
  let client_source = e.function(pattern, body)
  // TODO captured should not include empty
  let #(typed, typer) = analysis.infer(client_source, t.Unbound(-1), [])
  let #(typed, typer) = typer.expand_providers(typed, typer, [])
  let program =
    list.map(map.to_list(captured), r.render_var)
    |> list.append([javascript.render_to_string(typed, typer)])
    |> string.join("\n")
    |> string.append(
      "({
  on_click: (f) => { document.onclick = () => f() },
  display: (value) => document.body.innerHTML = value,
  // TODO does with work can we have outside poller
  on_code: (f) => { document.oncode = f }
});",
    )
  // This didn't work because of rendering captured variables for a fn within some scope.
  // We need a whole review of rendering or use interpreter
  //     "(({init}) => {
  //   console.log(init, 'initial state')
  //   const update = ({page, interrupt}) => {
  //     document.body.innerHTML = page
  //     document.onclick = () => update(interrupt({Click: 'key'}))
  //     document.oncode = (code) => update(interrupt({Code: code}))
  // TODO this needs the codegen part of loader
  //   }
  //   update(init)  
  //   // TODO set interval
  // })"
  let page =
    string.concat(["<head></head><body></body><script>", program, "</script>"])
  // assert r.Function() = term
  Ok(r.Binary(page))
}

fn env() {
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
    r.Record([
      #("append", r.BuiltinFn(string_append)),
      #("uppercase", r.BuiltinFn(string_uppercase)),
      #("lowercase", r.BuiltinFn(string_lowercase)),
      #("replace", r.BuiltinFn(string_replace)),
      // These could be parts of the server environment only because they are encoded
      #("serialize", r.BuiltinFn(term_serialize)),
    ]),
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
