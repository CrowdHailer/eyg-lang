import gleam/bit_string
import gleam/base
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string as gleam_string
import eygir/expression as e
import eyg/analysis/typ as t
import eygir/encode
import eyg/runtime/interpreter as r
import eyg/runtime/capture
import harness/ffi/cast
import harness/env.{extend, init}
import harness/ffi/integer
import harness/ffi/linked_list
import harness/ffi/string
import old_plinth/browser/window
import plinth/javascript/console

pub fn equal() {
  let type_ =
    t.Fun(t.Unbound(0), t.Open(1), t.Fun(t.Unbound(0), t.Open(2), t.boolean))
  #(type_, r.Arity2(do_equal))
}

fn do_equal(left, right, rev, env, k) {
  case left == right {
    True -> r.true
    False -> r.false
  }
  |> r.Value
  |> r.prim(rev, env, k)
}

pub fn debug() {
  let type_ = t.Fun(t.Unbound(0), t.Open(1), t.Str)
  #(type_, r.Arity1(do_debug))
}

fn do_debug(term, rev, env, k) {
  r.prim(r.Value(r.Str(r.to_string(term))), rev, env, k)
}

pub fn fix() {
  let type_ =
    t.Fun(
      t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-1)),
      t.Open(-3),
      t.Unbound(-1),
    )
  #(type_, r.Arity1(do_fix))
}

fn do_fix(builder, rev, env, k) {
  r.step_call(builder, r.Defunc(r.Builtin("fixed"), [builder]), rev, env, k)
}

pub fn fixed() {
  // I'm not sure a type ever means anything here
  // fixed is not a function you can reference directly it's just a runtime
  // value produced by the fix action
  #(
    t.Unbound(0),
    r.Arity2(fn(builder, arg, rev, env, k) {
      r.step_call(
        builder,
        // always pass a reference to itself
        r.Defunc(r.Builtin("fixed"), [builder]),
        rev,
        env,
        // fn(partial) {
        //   let #(c, rev, e, k) = r.step_call(partial, arg, rev, env, k)
        //   r.K(c, rev, e, k)
        // },
        Some(r.Kont(r.CallWith(arg, rev, env), k)),
      )
    }),
  )
  //   #(
  //   t.Unbound(0),
  //   r.Arity1(fn(builder, rev, env, k) {
  //     r.step_call(
  //       builder,
  //       // always pass a reference to itself
  //       r.Defunc(r.Builtin("fixed"), [builder]),
  //       rev,
  //       env,
  //       // fn(partial) {
  //       //   let #(c, rev, e, k) = r.step_call(partial, arg, rev, env, k)
  //       //   r.K(c, rev, e, k)
  //       // },
  //       // Some(r.Kont(r.CallWith(arg, rev, env), k)),
  //       k
  //     )
  //   }),
  // )
}

pub fn eval() {
  let type_ = t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-3))

  #(type_, r.Arity1(do_eval))
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
  |> extend("base64_encode", base64_encode())
  // binary
  |> extend("binary_from_integers", binary_from_integers())
  // integer
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
  |> extend("string_replace", string.replace())
  |> extend("string_uppercase", string.uppercase())
  |> extend("string_lowercase", string.lowercase())
  |> extend("string_ends_with", string.ends_with())
  |> extend("string_length", string.length())
  |> extend("pop_grapheme", string.pop_grapheme())
  // list
  |> extend("list_pop", linked_list.pop())
  |> extend("list_fold", linked_list.fold())
  |> extend("eval", eval())
}

pub fn do_eval(source, rev, env, k) {
  use source <- cast.require(cast.list(source), rev, env, k)
  case language_to_expression(source) {
    Ok(expression) -> {
      // must be value otherwise/effect continuations need sorting
      let assert r.Value(value) =
        r.eval(
          expression,
          r.Env([], lib().1),
          Some(r.Kont(r.Apply(r.Defunc(r.Tag("Ok"), []), rev, env), None)),
        )
      // console.log(value)
      r.prim(r.Value(value), rev, env, k)
    }
    Error(_) -> r.prim(r.Value(r.error(r.unit)), rev, env, k)
  }
}

// This should be replaced by capture which returns ast
pub fn serialize() {
  let type_ = t.Fun(t.Unbound(-1), t.Open(-2), t.Str)

  #(type_, r.Arity1(do_serialize))
}

pub fn do_serialize(term, rev, env, k) {
  let exp = capture.capture(term)
  r.prim(r.Value(r.Str(encode.to_json(exp))), rev, env, k)
}

pub fn capture() {
  // TODO need enum type
  let type_ = t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-3))

  #(type_, r.Arity1(do_capture))
}

pub fn do_capture(term, rev, env, k) {
  let exp = capture.capture(term)
  r.prim(r.Value(r.LinkedList(expression_to_language(exp))), rev, env, k)
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
// Defunc continuation
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
    e.Variable(label) -> [r.Tagged("Variable", r.Str(label))]
    e.Lambda(label, body) -> {
      let head = r.Tagged("Lambda", r.Str(label))
      let rest = expression_to_language(body)
      [head, ..rest]
    }
    e.Apply(func, argument) -> {
      let head = r.Tagged("Apply", r.Record([]))
      let rest =
        list.append(
          expression_to_language(func),
          expression_to_language(argument),
        )
      [head, ..rest]
    }
    e.Let(label, definition, body) -> {
      let head = r.Tagged("Let", r.Str(label))
      [
        head,
        ..list.append(
          expression_to_language(definition),
          expression_to_language(body),
        )
      ]
    }

    e.Binary(value) -> [r.Tagged("Binary", r.Binary(value))]
    e.Integer(value) -> [r.Tagged("Integer", r.Integer(value))]
    e.Str(value) -> [r.Tagged("String", r.Str(value))]

    e.Tail -> [r.Tagged("Tail", r.Record([]))]
    e.Cons -> [r.Tagged("Cons", r.Record([]))]

    e.Vacant(comment) -> [r.Tagged("Vacant", r.Str(comment))]

    e.Empty -> [r.Tagged("Empty", r.Record([]))]
    e.Extend(label) -> [r.Tagged("Extend", r.Str(label))]
    e.Select(label) -> [r.Tagged("Select", r.Str(label))]
    e.Overwrite(label) -> [r.Tagged("Overwrite", r.Str(label))]
    e.Tag(label) -> [r.Tagged("Tag", r.Str(label))]
    e.Case(label) -> [r.Tagged("Case", r.Str(label))]
    e.NoCases -> [r.Tagged("NoCases", r.Record([]))]

    e.Perform(label) -> [r.Tagged("Perform", r.Str(label))]
    e.Handle(label) -> [r.Tagged("Handle", r.Str(label))]
    e.Shallow(label) -> [r.Tagged("Shallow", r.Str(label))]
    e.Builtin(identifier) -> [r.Tagged("Builtin", r.Str(identifier))]
  }
}

pub fn language_to_expression(source) {
  // This stack overflows on resolving the built up k
  // do_language_to_expression(source, fn(x, _) { Ok(x) })
  Ok(stack_language_to_expression(source, []))
}

fn stack_language_to_expression(source, stack) {
  let [node, ..source] = source
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
    r.Tagged("Variable", r.Str(label)) -> {
      #(Some(e.Variable(label)), stack)
    }
    r.Tagged("Lambda", r.Str(label)) -> {
      #(None, [DoBody(label), ..stack])
    }
    r.Tagged("Apply", r.Record([])) -> {
      // use arg, rest <- do_language_to_expression(rest)
      #(None, [DoFunc, ..stack])
    }
    r.Tagged("Let", r.Str(label)) -> {
      // use then, rest <- do_language_to_expression(rest)
      #(None, [DoValue(label), ..stack])
    }

    r.Tagged("Integer", r.Integer(value)) -> #(Some(e.Integer(value)), stack)
    r.Tagged("String", r.Str(value)) -> #(Some(e.Str(value)), stack)
    r.Tagged("Binary", r.Binary(value)) -> #(Some(e.Binary(value)), stack)

    r.Tagged("Tail", r.Record([])) -> #(Some(e.Tail), stack)
    r.Tagged("Cons", r.Record([])) -> #(Some(e.Cons), stack)

    r.Tagged("Vacant", r.Str(comment)) -> #(Some(e.Vacant(comment)), stack)

    r.Tagged("Empty", r.Record([])) -> #(Some(e.Empty), stack)
    r.Tagged("Extend", r.Str(label)) -> #(Some(e.Extend(label)), stack)
    r.Tagged("Select", r.Str(label)) -> #(Some(e.Select(label)), stack)
    r.Tagged("Overwrite", r.Str(label)) -> #(Some(e.Overwrite(label)), stack)
    r.Tagged("Tag", r.Str(label)) -> #(Some(e.Tag(label)), stack)
    r.Tagged("Case", r.Str(label)) -> #(Some(e.Case(label)), stack)
    r.Tagged("NoCases", r.Record([])) -> #(Some(e.NoCases), stack)

    r.Tagged("Perform", r.Str(label)) -> #(Some(e.Perform(label)), stack)
    r.Tagged("Handle", r.Str(label)) -> #(Some(e.Handle(label)), stack)
    r.Tagged("Shallow", r.Str(label)) -> #(Some(e.Shallow(label)), stack)
    r.Tagged("Builtin", r.Str(identifier)) -> #(
      Some(e.Builtin(identifier)),
      stack,
    )
    remaining -> {
      io.debug(#("remaining values", remaining, stack))
      Error("error debuggin expressions")
      panic("bad decodeding")
    }
  }
}

fn do_language_to_expression(term, k) {
  case term {
    [r.Tagged("Variable", r.Str(label)), ..rest] -> {
      k(e.Variable(label), rest)
    }
    [r.Tagged("Lambda", r.Str(label)), ..rest] -> {
      use body, rest <- do_language_to_expression(rest)
      k(e.Lambda(label, body), rest)
    }
    [r.Tagged("Apply", r.Record([])), ..rest] -> {
      use func, rest <- do_language_to_expression(rest)
      use arg, rest <- do_language_to_expression(rest)
      k(e.Apply(func, arg), rest)
    }
    [r.Tagged("Let", r.Str(label)), ..rest] -> {
      use value, rest <- do_language_to_expression(rest)
      use then, rest <- do_language_to_expression(rest)
      k(e.Let(label, value, then), rest)
    }

    [r.Tagged("Integer", r.Integer(value)), ..rest] -> k(e.Integer(value), rest)
    [r.Tagged("String", r.Str(value)), ..rest] -> k(e.Str(value), rest)
    [r.Tagged("Binary", r.Binary(value)), ..rest] -> k(e.Binary(value), rest)

    [r.Tagged("Tail", r.Record([])), ..rest] -> k(e.Tail, rest)
    [r.Tagged("Cons", r.Record([])), ..rest] -> k(e.Cons, rest)

    [r.Tagged("Vacant", r.Str(comment)), ..rest] -> k(e.Vacant(comment), rest)

    [r.Tagged("Empty", r.Record([])), ..rest] -> k(e.Empty, rest)
    [r.Tagged("Extend", r.Str(label)), ..rest] -> k(e.Extend(label), rest)
    [r.Tagged("Select", r.Str(label)), ..rest] -> k(e.Select(label), rest)
    [r.Tagged("Overwrite", r.Str(label)), ..rest] -> k(e.Overwrite(label), rest)
    [r.Tagged("Tag", r.Str(label)), ..rest] -> k(e.Tag(label), rest)
    [r.Tagged("Case", r.Str(label)), ..rest] -> k(e.Case(label), rest)
    [r.Tagged("NoCases", r.Record([])), ..rest] -> k(e.NoCases, rest)

    [r.Tagged("Perform", r.Str(label)), ..rest] -> k(e.Perform(label), rest)
    [r.Tagged("Handle", r.Str(label)), ..rest] -> k(e.Handle(label), rest)
    [r.Tagged("Shallow", r.Str(label)), ..rest] -> k(e.Shallow(label), rest)
    [r.Tagged("Builtin", r.Str(identifier)), ..rest] ->
      k(e.Builtin(identifier), rest)
    remaining -> {
      io.debug(#("remaining values", remaining, k))
      Error("error debuggin expressions")
    }
  }
}

pub fn encode_uri() {
  let type_ = t.Fun(t.Str, t.Open(-1), t.Str)
  #(type_, r.Arity1(do_encode_uri))
}

pub fn do_encode_uri(term, rev, env, k) {
  use unencoded <- cast.require(cast.string(term), rev, env, k)
  r.prim(r.Value(r.Str(window.encode_uri(unencoded))), rev, env, k)
}

pub fn base64_encode() {
  let type_ = t.Fun(t.Str, t.Open(-1), t.Str)
  #(type_, r.Arity1(do_base64_encode))
}

pub fn do_base64_encode(term, rev, env, k) {
  use unencoded <- cast.require(cast.string(term), rev, env, k)
  r.prim(
    r.Value(r.Str(gleam_string.replace(
      base.encode64(bit_string.from_string(unencoded), True),
      "\r\n",
      "",
    ))),
    rev,
    env,
    k,
  )
}

pub fn binary_from_integers() {
  let type_ = t.Fun(t.LinkedList(t.Integer), t.Open(-1), t.Binary)
  #(type_, r.Arity1(do_binary_from_integers))
}

pub fn do_binary_from_integers(term, rev, env, k) {
  use parts <- cast.require(cast.list(term), rev, env, k)
  let content =
    list.fold(
      list.reverse(parts),
      <<>>,
      fn(acc, el) {
        let assert r.Integer(i) = el
        <<i, acc:bit_string>>
      },
    )
  r.prim(r.Value(r.Binary(content)), rev, env, k)
}
