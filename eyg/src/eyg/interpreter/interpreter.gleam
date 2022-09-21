import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/option.{None, Option, Some}
import gleam/int
import gleam/list
import gleam/map
import gleam/string
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/codegen/javascript

pub type Object {
  Binary(String)
  Pid(Int)
  Tuple(List(Object))
  Record(List(#(String, Object)))
  Tagged(String, Object)
  Function(
    p.Pattern,
    e.Expression(Dynamic, Dynamic),
    map.Map(String, Object),
    Option(String),
  )
  Coroutine(Object)
  Ready(Object, Object)
  BuiltinFn(fn(Object) -> Result(Object, String))
  Native(Dynamic)
  Effect(String, Object, fn(Object) -> Result(Object, String))
}

pub fn extend_env(env, pattern, object) {
  case pattern {
    p.Variable(var) -> Ok(map.insert(env, var, object))
    p.Tuple(keys) ->
      case object {
        Tuple(elements) ->
          case list.strict_zip(keys, elements) {
            Ok(pairs) ->
              Ok(list.fold(
                pairs,
                env,
                fn(env, pair) {
                  let #(var, value) = pair
                  map.insert(env, var, value)
                },
              ))
            Error(reason) -> Error("needs better error")
          }
        _ -> Error("not a tuple")
      }

    p.Record(fields) -> todo("not supporting record fields here yet")
  }
}

pub fn render_var(assignment) {
  case assignment {
    #("", _) -> ""
    #("send", BuiltinFn(_)) ->
      string.concat([
        "let send = ([pid, message]) => (then) => { 
            if (pid == 'ui') {
                document.body.innerHTML = message
            } else if(pid == 'log') {
                console.log(message)
            } else if(pid == 'on_keypress') {
                document.addEventListener(\"keydown\", function (event) {message(event.key);})
            } else {
                console.warn(pid, message) 
                fetch(`${window.location.pathname}/_/${pid}`, {method: 'POST', body: message})
            }
            return then([])
        }",
        ";",
      ])
    #(var, object) ->
      string.concat(["let ", var, " = ", render_object(object), ";"])
  }
}

fn render_object(object) {
  case object {
    Binary(content) ->
      string.concat(["\"", javascript.escape_string(content), "\""])
    Pid(pid) -> int.to_string(pid)
    Tuple(elements) -> {
      let term =
        list.map(elements, render_object)
        |> string.join(", ")
      string.concat(["[", term, "]"])
    }
    Record(fields) -> {
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
    Tagged(tag, value) ->
      string.concat(["{", tag, ":", render_object(value), "}"])
    // Builtins should never be included, I need to check variables used in a previous step
    // Function(_,_,_,_) -> todo("this needs compile again but I need a way to do this without another type check")
    Function(_, _, _, _) -> "null"
    BuiltinFn(_) -> todo("we aren't using builtin here should be part of env")
    Coroutine(_) -> "null"
    Ready(_, _) -> "null"
    Native(_) -> "null"
    Effect(_, _, _) -> todo("this shouldnt be rendered")
  }
}

// std
const true = Tagged("True", Tuple([]))

const false = Tagged("False", Tuple([]))

pub fn equal(object) {
  assert Tuple([left, right]) = object
  Ok(case left == right {
    True -> true
    False -> false
  })
}
