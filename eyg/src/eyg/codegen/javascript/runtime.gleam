import gleam/io
import gleam/list
import gleam/map
import gleam/string
import eyg/interpreter/interpreter as r
import eyg/interpreter/builtin
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer/monotype as t
import eyg/codegen/javascript
import eyg/analysis
import eyg/analysis/shake
import eyg/typer

pub fn render_var(assignment) {
  case assignment {
    // NOTE that effect handlers are not supported in compiled code
    #("", _) | #("do", _) | #("impl", _) -> ""
    // #("equal", _) -> "let equal = ([a, b]) => a == b;"
    #(var, object) ->
      string.concat(["let ", var, " = ", render_object(object), ";"])
  }
}

pub fn render_object(object) {
  case object {
    // TODO move string render to /codegen/javascript file
    // separate source and runtime
    r.Binary(content) ->
      string.concat(["\"", javascript.escape_string(content), "\""])
    //       |> string.replace("<", "&lt;")
    // |> string.replace(">", "&gt;")
    r.Tuple(elements) -> {
      let term =
        list.map(elements, render_object)
        |> string.join(", ")
      string.concat(["[", term, "]"])
    }
    r.Record(fields) -> {
      let term =
        list.map(
          fields,
          fn(field) {
            let #(name, object) = field
            string.concat([name, ": ", render_object(object)])
          },
        )
        |> string.join(", ")
      string.concat(["{", term, "}"])
    }
    r.Tagged(tag, value) ->
      string.concat(["{", tag, ":", render_object(value), "}"])
    // Builtins should never be included, I need to check variables used in a previous step
    // Function(_,_,_,_) -> todo("this needs compile again but I need a way to do this without another type check")
    r.Function(pattern, body, captured, self) -> {
      // TODO shouldn't need to infer again this is just to satisfy render ast fn
      let #(typed, typer) =
        analysis.infer(e.function(pattern, body), t.Unbound(-1), [])
      let #(typed, typer) = typer.expand_providers(typed, typer, [])
      assert r.Record(fields) =
        shake.shake_function(pattern, todo, captured, self)
      //   io.debug(fields)
      // TODO use maybe wrap expression an indent
      ["(() => {", ..list.map(fields, render_var)]
      |> list.append([
        javascript.render_fn_to_string(typed, typer, self),
        "})()",
      ])
      |> string.join("\n")
    }
    r.BuiltinFn(f) -> {
      //   assert Ok(r.Record(globals)) = map.get(effectful.env(), "builtin")
      let globals = builtin.builtin()
      assert Ok(label) = render_builtin(f, globals)
      string.append("Builtin.", label)
    }
    r.Native(_) -> todo("remove Native from runtime")
    r.Effect(_, _, _) -> todo("this shouldnt be rendered")
  }
}

pub fn render_builtin(f, globals) {
  list.find_map(
    globals,
    fn(global) {
      let #(label, value) = global
      case value == r.BuiltinFn(f) {
        True -> Ok(label)
        False -> Error(Nil)
      }
    },
  )
}
