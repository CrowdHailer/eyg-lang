import gleam/bit_array
import gleam/dict
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string as gleam_string
import plinth/browser/window
import plinth/javascript/global
import plinth/javascript/console
import eygir/expression as e
import eyg/analysis/typ as t
import eygir/encode
import eyg/runtime/interpreter/runner as r
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import eyg/runtime/capture
import eyg/runtime/cast
import harness/env.{extend, init}
import harness/ffi/integer
import harness/ffi/linked_list
import harness/ffi/string

pub fn equal() {
  let type_ =
    t.Fun(t.Unbound(0), t.Open(1), t.Fun(t.Unbound(0), t.Open(2), t.boolean))
  #(type_, state.Arity2(do_equal))
}

fn do_equal(left, right, rev, env, k) {
  let value = case left == right {
    True -> v.true
    False -> v.false
  }
  Ok(#(state.V(value), rev, env, k))
}

pub fn debug() {
  let type_ = t.Fun(t.Unbound(0), t.Open(1), t.Str)
  #(type_, state.Arity1(do_debug))
}

fn do_debug(term, rev, env, k) {
  Ok(#(state.V(v.Str(v.debug(term))), rev, env, k))
}

pub fn fix() {
  let type_ =
    t.Fun(
      t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-1)),
      t.Open(-3),
      t.Unbound(-1),
    )
  #(type_, state.Arity1(do_fix))
}

fn do_fix(builder, rev, env, k) {
  state.call(builder, v.Partial(v.Builtin("fixed"), [builder]), rev, env, k)
}

pub fn fixed() {
  // I'm not sure a type ever means anything here
  // fixed is not a function you can reference directly it's just a runtime
  // value produced by the fix action
  #(
    t.Unbound(0),
    state.Arity2(fn(builder, arg, rev, env, k) {
      state.call(
        builder,
        // always pass a reference to itself
        v.Partial(v.Builtin("fixed"), [builder]),
        rev,
        env,
        // fn(partial) {
        //   let #(c, rev, e, k) = state.call(partial, arg, rev, env, k)
        //   state.K(c, rev, e, k)
        // },
        state.Stack(state.CallWith(arg, rev, env), k),
      )
    }),
  )
  //   #(
  //   t.Unbound(0),
  //   state.Arity1(fn(builder, rev, env, k) {
  //     state.call(
  //       builder,
  //       // always pass a reference to itself
  //       v.Partial(v.Builtin("fixed"), [builder]),
  //       rev,
  //       env,
  //       // fn(partial) {
  //       //   let #(c, rev, e, k) = state.call(partial, arg, rev, env, k)
  //       //   state.K(c, rev, e, k)
  //       // },
  //       // Some(state.Stack(state.CallWith(arg, rev, env), k)),
  //       k
  //     )
  //   }),
  // )
}

pub fn eval() {
  let type_ = t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-3))

  #(type_, state.Arity1(do_eval))
}

pub fn lib() {
  init()
  |> extend("equal", equal())
  |> extend("debug", debug())
  |> extend("fix", fix())
  |> extend("fixed", fixed())
  |> extend("serialize", serialize())
  |> extend("capture", capture())
  |> extend("encode_uri", encode_uri())
  |> extend("decode_uri_component", decode_uri_component())
  |> extend("base64_encode", base64_encode())
  // binary
  |> extend("binary_from_integers", binary_from_integers())
  // integer
  |> extend("int_compare", integer.compare())
  |> extend("int_add", integer.add())
  |> extend("int_subtract", integer.subtract())
  |> extend("int_multiply", integer.multiply())
  |> extend("int_divide", integer.divide())
  |> extend("int_absolute", integer.absolute())
  |> extend("int_parse", integer.parse())
  |> extend("int_to_string", integer.to_string())
  // string
  |> extend("string_append", string.append())
  |> extend("string_split", string.split())
  |> extend("string_split_once", string.split_once())
  |> extend("string_replace", string.replace())
  |> extend("string_uppercase", string.uppercase())
  |> extend("string_lowercase", string.lowercase())
  |> extend("string_starts_with", string.starts_with())
  |> extend("string_ends_with", string.ends_with())
  |> extend("string_length", string.length())
  |> extend("pop_grapheme", string.pop_grapheme())
  |> extend("string_to_binary", string.to_binary())
  // list
  |> extend("list_pop", linked_list.pop())
  |> extend("list_fold", linked_list.fold())
  |> extend("eval", eval())
}

pub fn do_eval(source, rev, env, k) {
  use source <- result.then(cast.as_list(source))
  case language_to_expression(source) {
    Ok(expression) -> {
      // must be value otherwise/effect continuations need sorting
      let result = r.execute(expression, state.Env([], lib().1), dict.new())
      let value = case result {
        Ok(value) -> v.ok(value)
        _ -> {
          console.log("failed to run expression")
          console.log(expression)
          console.log(result)
          v.error(v.unit)
        }
      }
      // console.log(value)
      Ok(#(state.V(value), rev, env, k))
    }
    Error(_) -> Ok(#(state.V(v.error(v.unit)), rev, env, k))
  }
}

// This should be replaced by capture which returns ast
pub fn serialize() {
  let type_ = t.Fun(t.Unbound(-1), t.Open(-2), t.Str)

  #(type_, state.Arity1(do_serialize))
}

pub fn do_serialize(term, rev, env, k) {
  let exp = capture.capture(term)
  Ok(#(state.V(v.Str(encode.to_json(exp))), rev, env, k))
}

pub fn capture() {
  // TODO need enum type
  let type_ = t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-3))

  #(type_, state.Arity1(do_capture))
}

pub fn do_capture(term, rev, env, k) {
  let exp = capture.capture(term)
  Ok(#(state.V(v.LinkedList(expression_to_language(exp))), rev, env, k))
}

// block needs squashing with row on the front
// have non empty list type
// have growing front and back list
// Integer v -> done(integer(v))
// Apply -> block(f -> block(a ->))
// then(block(indent), fn b -> then(expression(indent), fn t -> {
//   ["let l = ", b, t]

// })

// // eygir
// case next {
//   Select l -> {
//     select(l)
//     then(block)(arg -> {
//       []
//     })
//   }
// vacant is not a type checker error it's a query we can use
//   _ ->
// }
// Let label -> rest -> block(indent)(rest)(value -> {
//   expression(then -> {
//     let assignment = match length(value) == 0 {
//        indent(value)
//     }
//     done(list.append())
//   }
// })
// Apply -> source ->
//  match {
//    _ -> block(ident)(source)
// }
// })
// block = indent -> parts match{let is write {}}
// block(indent + 2) then(expression)

// could be term to lang
// Partial continuation
// recursive data structure vs list
// recusive correct by construction
// could just read till next end term
// Cases and provider
// i.e.
// match exp {
//   Handle format("handle %s")
// }
// crafting interpreters probably has a handle on this
// flat design is first step to hashable
// defunc continuation
// use the render block version and drop out when finished
// anything simple -> cont
// most other things use render block with indent
// try and write to buffer once but why performance
// actually always return lines
// if single render block does it's thing
// if not we nest in
// is there an elegant write once I think it pairs with defunc'd
// rendering? is it that interesting to do twice?
// TODO have a single code element that renders the value
pub fn expression_to_language(exp) {
  case exp {
    e.Variable(label) -> [v.Tagged("Variable", v.Str(label))]
    e.Lambda(label, body) -> {
      let head = v.Tagged("Lambda", v.Str(label))
      let rest = expression_to_language(body)
      [head, ..rest]
    }
    e.Apply(func, argument) -> {
      let head = v.Tagged("Apply", v.unit)
      let rest =
        list.append(
          expression_to_language(func),
          expression_to_language(argument),
        )
      [head, ..rest]
    }
    e.Let(label, definition, body) -> {
      let head = v.Tagged("Let", v.Str(label))
      [
        head,
        ..list.append(
          expression_to_language(definition),
          expression_to_language(body),
        )
      ]
    }

    e.Binary(value) -> [v.Tagged("Binary", v.Binary(value))]
    e.Integer(value) -> [v.Tagged("Integer", v.Integer(value))]
    e.Str(value) -> [v.Tagged("String", v.Str(value))]

    e.Tail -> [v.Tagged("Tail", v.unit)]
    e.Cons -> [v.Tagged("Cons", v.unit)]

    e.Vacant(comment) -> [v.Tagged("Vacant", v.Str(comment))]

    e.Empty -> [v.Tagged("Empty", v.unit)]
    e.Extend(label) -> [v.Tagged("Extend", v.Str(label))]
    e.Select(label) -> [v.Tagged("Select", v.Str(label))]
    e.Overwrite(label) -> [v.Tagged("Overwrite", v.Str(label))]
    e.Tag(label) -> [v.Tagged("Tag", v.Str(label))]
    e.Case(label) -> [v.Tagged("Case", v.Str(label))]
    e.NoCases -> [v.Tagged("NoCases", v.unit)]

    e.Perform(label) -> [v.Tagged("Perform", v.Str(label))]
    e.Handle(label) -> [v.Tagged("Handle", v.Str(label))]
    e.Shallow(label) -> [v.Tagged("Shallow", v.Str(label))]
    e.Builtin(identifier) -> [v.Tagged("Builtin", v.Str(identifier))]
  }
}

pub fn language_to_expression(source) {
  // This stack overflows on resolving the built up k
  // do_language_to_expression(source, fn(x, _) { Ok(x) })
  Ok(stack_language_to_expression(source, []))
}

fn stack_language_to_expression(source, stack) {
  let assert [node, ..source] = source
  let #(exp, stack) = step(node, stack)
  case exp {
    Some(exp) ->
      case apply(exp, stack) {
        Ok(exp) -> {
          exp
        }
        Error(stack) -> stack_language_to_expression(source, stack)
      }
    None -> stack_language_to_expression(source, stack)
  }
}

fn apply(exp, stack) {
  case stack {
    [] -> Ok(exp)
    [DoBody(label), ..stack] -> apply(e.Lambda(label, exp), stack)
    [DoFunc, ..stack] -> Error([DoArg(exp), ..stack])
    [DoArg(func), ..stack] -> apply(e.Apply(func, exp), stack)
    [DoValue(label), ..stack] -> Error([DoThen(label, exp), ..stack])
    [DoThen(label, value), ..stack] -> apply(e.Let(label, value, exp), stack)
  }
}

type NativeStack {
  DoBody(String)
  DoFunc
  DoArg(e.Expression)
  DoValue(String)
  DoThen(String, e.Expression)
}

fn step(node, stack) {
  case node {
    v.Tagged("Variable", v.Str(label)) -> {
      #(Some(e.Variable(label)), stack)
    }
    v.Tagged("Lambda", v.Str(label)) -> {
      #(None, [DoBody(label), ..stack])
    }

    // TODO can we pattern match on constants
    v.Tagged("Apply", v.Record([])) -> {
      // use arg, rest <- do_language_to_expression(rest)
      #(None, [DoFunc, ..stack])
    }
    v.Tagged("Let", v.Str(label)) -> {
      // use then, rest <- do_language_to_expression(rest)
      #(None, [DoValue(label), ..stack])
    }

    v.Tagged("Integer", v.Integer(value)) -> #(Some(e.Integer(value)), stack)
    v.Tagged("String", v.Str(value)) -> #(Some(e.Str(value)), stack)
    v.Tagged("Binary", v.Binary(value)) -> #(Some(e.Binary(value)), stack)

    v.Tagged("Tail", v.Record([])) -> #(Some(e.Tail), stack)
    v.Tagged("Cons", v.Record([])) -> #(Some(e.Cons), stack)

    v.Tagged("Vacant", v.Str(comment)) -> #(Some(e.Vacant(comment)), stack)

    v.Tagged("Empty", v.Record([])) -> #(Some(e.Empty), stack)
    v.Tagged("Extend", v.Str(label)) -> #(Some(e.Extend(label)), stack)
    v.Tagged("Select", v.Str(label)) -> #(Some(e.Select(label)), stack)
    v.Tagged("Overwrite", v.Str(label)) -> #(Some(e.Overwrite(label)), stack)
    v.Tagged("Tag", v.Str(label)) -> #(Some(e.Tag(label)), stack)
    v.Tagged("Case", v.Str(label)) -> #(Some(e.Case(label)), stack)
    v.Tagged("NoCases", v.Record([])) -> #(Some(e.NoCases), stack)

    v.Tagged("Perform", v.Str(label)) -> #(Some(e.Perform(label)), stack)
    v.Tagged("Handle", v.Str(label)) -> #(Some(e.Handle(label)), stack)
    v.Tagged("Shallow", v.Str(label)) -> #(Some(e.Shallow(label)), stack)
    v.Tagged("Builtin", v.Str(identifier)) -> #(
      Some(e.Builtin(identifier)),
      stack,
    )
    remaining -> {
      io.debug(#("remaining values", remaining, stack))
      // Error("error debuggin expressions")
      panic("bad decodeding")
    }
  }
}

fn do_language_to_expression(term, k) {
  case term {
    [v.Tagged("Variable", v.Str(label)), ..rest] -> {
      k(e.Variable(label), rest)
    }
    [v.Tagged("Lambda", v.Str(label)), ..rest] -> {
      use body, rest <- do_language_to_expression(rest)
      k(e.Lambda(label, body), rest)
    }
    [v.Tagged("Apply", v.Record([])), ..rest] -> {
      use func, rest <- do_language_to_expression(rest)
      use arg, rest <- do_language_to_expression(rest)
      k(e.Apply(func, arg), rest)
    }
    [v.Tagged("Let", v.Str(label)), ..rest] -> {
      use value, rest <- do_language_to_expression(rest)
      use then, rest <- do_language_to_expression(rest)
      k(e.Let(label, value, then), rest)
    }

    [v.Tagged("Integer", v.Integer(value)), ..rest] -> k(e.Integer(value), rest)
    [v.Tagged("String", v.Str(value)), ..rest] -> k(e.Str(value), rest)
    [v.Tagged("Binary", v.Binary(value)), ..rest] -> k(e.Binary(value), rest)

    [v.Tagged("Tail", v.Record([])), ..rest] -> k(e.Tail, rest)
    [v.Tagged("Cons", v.Record([])), ..rest] -> k(e.Cons, rest)

    [v.Tagged("Vacant", v.Str(comment)), ..rest] -> k(e.Vacant(comment), rest)

    [v.Tagged("Empty", v.Record([])), ..rest] -> k(e.Empty, rest)
    [v.Tagged("Extend", v.Str(label)), ..rest] -> k(e.Extend(label), rest)
    [v.Tagged("Select", v.Str(label)), ..rest] -> k(e.Select(label), rest)
    [v.Tagged("Overwrite", v.Str(label)), ..rest] -> k(e.Overwrite(label), rest)
    [v.Tagged("Tag", v.Str(label)), ..rest] -> k(e.Tag(label), rest)
    [v.Tagged("Case", v.Str(label)), ..rest] -> k(e.Case(label), rest)
    [v.Tagged("NoCases", v.Record([])), ..rest] -> k(e.NoCases, rest)

    [v.Tagged("Perform", v.Str(label)), ..rest] -> k(e.Perform(label), rest)
    [v.Tagged("Handle", v.Str(label)), ..rest] -> k(e.Handle(label), rest)
    [v.Tagged("Shallow", v.Str(label)), ..rest] -> k(e.Shallow(label), rest)
    [v.Tagged("Builtin", v.Str(identifier)), ..rest] ->
      k(e.Builtin(identifier), rest)
    remaining -> {
      io.debug(#("remaining values", remaining, k))
      Error("error debuggin expressions")
    }
  }
}

pub fn decode_uri_component() {
  let type_ = t.Fun(t.Str, t.Open(-1), t.Str)
  #(type_, state.Arity1(do_decode_uri_component))
}

pub fn do_decode_uri_component(term, rev, env, k) {
  use unencoded <- result.then(cast.as_string(term))
  Ok(#(state.V(v.Str(global.decode_uri_component(unencoded))), rev, env, k))
}

pub fn encode_uri() {
  let type_ = t.Fun(t.Str, t.Open(-1), t.Str)
  #(type_, state.Arity1(do_encode_uri))
}

pub fn do_encode_uri(term, rev, env, k) {
  use unencoded <- result.then(cast.as_string(term))
  Ok(#(state.V(v.Str(global.encode_uri(unencoded))), rev, env, k))
}

pub fn base64_encode() {
  let type_ = t.Fun(t.Str, t.Open(-1), t.Str)
  #(type_, state.Arity1(do_base64_encode))
}

pub fn do_base64_encode(term, rev, env, k) {
  use unencoded <- result.then(cast.as_string(term))
  let value =
    v.Str(gleam_string.replace(
      bit_array.base64_encode(bit_array.from_string(unencoded), True),
      "\r\n",
      "",
    ))
  Ok(#(state.V(value), rev, env, k))
}

pub fn binary_from_integers() {
  let type_ = t.Fun(t.LinkedList(t.Integer), t.Open(-1), t.Binary)
  #(type_, state.Arity1(do_binary_from_integers))
}

pub fn do_binary_from_integers(term, rev, env, k) {
  use parts <- result.then(cast.as_list(term))
  let content =
    list.fold(list.reverse(parts), <<>>, fn(acc, el) {
      let assert v.Integer(i) = el
      <<i, acc:bits>>
    })
  Ok(#(state.V(v.Binary(content)), rev, env, k))
}
