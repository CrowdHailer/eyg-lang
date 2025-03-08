import eyg/analysis/typ as t
import eyg/compile
import eyg/interpreter/builtin
import eyg/interpreter/capture
import eyg/interpreter/cast
import eyg/interpreter/expression as r
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/runtime/value as old_value
import gleam/bit_array
import gleam/dict
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string as gleam_string
import harness/env.{extend, init}
import harness/ffi/integer
import harness/ffi/linked_list
import harness/ffi/string
import plinth/javascript/console
import plinth/javascript/global

pub fn equal() {
  let type_ =
    t.Fun(t.Unbound(0), t.Open(1), t.Fun(t.Unbound(0), t.Open(2), t.boolean))
  #(type_, builtin.equal)
}

pub fn debug() {
  let type_ = t.Fun(t.Unbound(0), t.Open(1), t.Str)
  #(type_, state.Arity1(do_debug))
}

fn do_debug(term, _meta, env, k) {
  Ok(#(state.V(v.String(old_value.debug(term))), env, k))
}

pub fn fix() {
  let type_ =
    t.Fun(
      t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-1)),
      t.Open(-3),
      t.Unbound(-1),
    )
  #(type_, builtin.fix)
}

pub fn fixed() {
  #(t.Unbound(0), builtin.fixed)
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
  |> extend("to_javascript", to_javascript())
  |> extend("encode_uri", encode_uri())
  |> extend("decode_uri_component", decode_uri_component())
  |> extend("base64_encode", base64_encode())
  |> extend("eval", eval())
  // binary
  |> extend("binary_from_integers", binary_from_integers())
  // integer
  |> extend("int_compare", integer.compare())
  |> extend("int_add", integer.add())
  |> extend("int_subtract", integer.subtract())
  |> extend("int_multiply", integer.multiply())
  |> extend("int_divide", integer.divide())
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
  |> extend("string_from_binary", string.from_binary())
  // pop_prefix is the same as split once need some testing on speed
  |> extend("pop_prefix", string.pop_prefix())
  // list
  |> extend("uncons", linked_list.uncons())
  |> extend("list_pop", linked_list.pop())
  |> extend("list_fold", linked_list.fold())
}

pub fn do_eval(source, _meta, env, k) {
  use source <- result.then(cast.as_list(source))
  case language_to_expression(source) {
    Ok(expression) -> {
      // must be value otherwise/effect continuations need sorting
      let result = r.execute(expression, [])
      let value = case result {
        Ok(value) -> v.ok(value)
        _ -> {
          console.log("failed to run expression")
          console.log(expression)
          console.log(result)
          v.error(v.unit())
        }
      }
      // console.log(value)
      Ok(#(state.V(value), env, k))
    }
    Error(_) -> Ok(#(state.V(v.error(v.unit())), env, k))
  }
}

// This should be replaced by capture which returns ast
pub fn serialize() {
  let type_ = t.Fun(t.Unbound(-1), t.Open(-2), t.Str)

  #(type_, state.Arity1(do_serialize))
}

pub fn do_serialize(term, rev, env, k) {
  let exp = capture.capture(term, rev)
  let assert Ok(src) = bit_array.to_string(dag_json.to_block(exp))
  Ok(#(state.V(v.String(src)), env, k))
}

pub fn capture() {
  // need enum type
  let type_ = t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-3))

  #(type_, state.Arity1(do_capture))
}

pub fn do_capture(term, rev, env, k) {
  let exp = capture.capture(term, rev)
  // wasteful but ideally capture will return annotated in the future
  Ok(#(state.V(v.LinkedList(expression_to_language(exp))), env, k))
}

pub fn to_javascript() {
  // need enum type
  let type_ = t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-3))

  #(type_, state.Arity2(do_to_javascript))
}

pub fn do_to_javascript(func, arg, meta, env, k) {
  let func = capture.capture(func, meta)
  let arg = capture.capture(arg, meta)
  let exp = #(ir.Apply(func, arg), meta)

  Ok(#(state.V(v.String(compile.to_js(exp, dict.new()))), env, k))
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
  let #(exp, _meta) = exp
  case exp {
    ir.Variable(label) -> [v.Tagged("Variable", v.String(label))]
    ir.Lambda(label, body) -> {
      let head = v.Tagged("Lambda", v.String(label))
      let rest = expression_to_language(body)
      [head, ..rest]
    }
    ir.Apply(func, argument) -> {
      let head = v.Tagged("Apply", v.unit())
      let rest =
        list.append(
          expression_to_language(func),
          expression_to_language(argument),
        )
      [head, ..rest]
    }
    ir.Let(label, definition, body) -> {
      let head = v.Tagged("Let", v.String(label))
      [
        head,
        ..list.append(
          expression_to_language(definition),
          expression_to_language(body),
        )
      ]
    }

    ir.Binary(value) -> [v.Tagged("Binary", v.Binary(value))]
    ir.Integer(value) -> [v.Tagged("Integer", v.Integer(value))]
    ir.String(value) -> [v.Tagged("String", v.String(value))]

    ir.Tail -> [v.Tagged("Tail", v.unit())]
    ir.Cons -> [v.Tagged("Cons", v.unit())]

    ir.Vacant -> [v.Tagged("Vacant", v.unit())]

    ir.Empty -> [v.Tagged("Empty", v.unit())]
    ir.Extend(label) -> [v.Tagged("Extend", v.String(label))]
    ir.Select(label) -> [v.Tagged("Select", v.String(label))]
    ir.Overwrite(label) -> [v.Tagged("Overwrite", v.String(label))]
    ir.Tag(label) -> [v.Tagged("Tag", v.String(label))]
    ir.Case(label) -> [v.Tagged("Case", v.String(label))]
    ir.NoCases -> [v.Tagged("NoCases", v.unit())]

    ir.Perform(label) -> [v.Tagged("Perform", v.String(label))]
    ir.Handle(label) -> [v.Tagged("Handle", v.String(label))]
    ir.Builtin(identifier) -> [v.Tagged("Builtin", v.String(identifier))]
    ir.Reference(identifier) -> [v.Tagged("Reference", v.String(identifier))]
    ir.Release(package, release, identifier) -> [
      v.Tagged(
        "Release",
        v.Record(
          dict.from_list([
            #("package", v.String(package)),
            #("release", v.Integer(release)),
            #("identifier", v.String(identifier)),
          ]),
        ),
      ),
    ]
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
      case apply(#(exp, Nil), stack) {
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
    [DoBody(label), ..stack] -> apply(#(ir.Lambda(label, exp), Nil), stack)
    [DoFunc, ..stack] -> Error([DoArg(exp), ..stack])
    [DoArg(func), ..stack] -> apply(#(ir.Apply(func, exp), Nil), stack)
    [DoValue(label), ..stack] -> Error([DoThen(label, exp), ..stack])
    [DoThen(label, value), ..stack] ->
      apply(#(ir.Let(label, value, exp), Nil), stack)
  }
}

type NativeStack(m) {
  DoBody(String)
  DoFunc
  DoArg(ir.Node(m))
  DoValue(String)
  DoThen(String, ir.Node(m))
}

fn step(node, stack) {
  case node {
    v.Tagged("Variable", v.String(label)) -> {
      #(Some(ir.Variable(label)), stack)
    }
    v.Tagged("Lambda", v.String(label)) -> {
      #(None, [DoBody(label), ..stack])
    }

    // TODO can we pattern match on constants
    v.Tagged("Apply", v.Record(_)) -> {
      // use arg, rest <- do_language_to_expression(rest)
      #(None, [DoFunc, ..stack])
    }
    v.Tagged("Let", v.String(label)) -> {
      // use then, rest <- do_language_to_expression(rest)
      #(None, [DoValue(label), ..stack])
    }

    v.Tagged("Integer", v.Integer(value)) -> #(Some(ir.Integer(value)), stack)
    v.Tagged("String", v.String(value)) -> #(Some(ir.String(value)), stack)
    v.Tagged("Binary", v.Binary(value)) -> #(Some(ir.Binary(value)), stack)

    v.Tagged("Tail", v.Record(_)) -> #(Some(ir.Tail), stack)
    v.Tagged("Cons", v.Record(_)) -> #(Some(ir.Cons), stack)

    v.Tagged("Vacant", v.Record(_)) -> #(Some(ir.Vacant), stack)

    v.Tagged("Empty", v.Record(_)) -> #(Some(ir.Empty), stack)
    v.Tagged("Extend", v.String(label)) -> #(Some(ir.Extend(label)), stack)
    v.Tagged("Select", v.String(label)) -> #(Some(ir.Select(label)), stack)
    v.Tagged("Overwrite", v.String(label)) -> #(
      Some(ir.Overwrite(label)),
      stack,
    )
    v.Tagged("Tag", v.String(label)) -> #(Some(ir.Tag(label)), stack)
    v.Tagged("Case", v.String(label)) -> #(Some(ir.Case(label)), stack)
    v.Tagged("NoCases", v.Record(_)) -> #(Some(ir.NoCases), stack)

    v.Tagged("Perform", v.String(label)) -> #(Some(ir.Perform(label)), stack)
    v.Tagged("Handle", v.String(label)) -> #(Some(ir.Handle(label)), stack)
    v.Tagged("Builtin", v.String(identifier)) -> #(
      Some(ir.Builtin(identifier)),
      stack,
    )
    remaining -> {
      io.debug(#("remaining values", remaining, stack))
      // Error("error debuggin expressions")
      panic as "bad decodeding"
    }
  }
}

fn do_language_to_expression(term, k) {
  case term {
    [v.Tagged("Variable", v.String(label)), ..rest] -> {
      k(ir.Variable(label), rest)
    }
    [v.Tagged("Lambda", v.String(label)), ..rest] -> {
      use body, rest <- do_language_to_expression(rest)
      k(ir.Lambda(label, #(body, Nil)), rest)
    }
    [v.Tagged("Apply", v.Record(_)), ..rest] -> {
      use func, rest <- do_language_to_expression(rest)
      use arg, rest <- do_language_to_expression(rest)
      k(ir.Apply(#(func, Nil), #(arg, Nil)), rest)
    }
    [v.Tagged("Let", v.String(label)), ..rest] -> {
      use value, rest <- do_language_to_expression(rest)
      use then, rest <- do_language_to_expression(rest)
      k(ir.Let(label, #(value, Nil), #(then, Nil)), rest)
    }

    [v.Tagged("Integer", v.Integer(value)), ..rest] ->
      k(ir.Integer(value), rest)
    [v.Tagged("String", v.String(value)), ..rest] -> k(ir.String(value), rest)
    [v.Tagged("Binary", v.Binary(value)), ..rest] -> k(ir.Binary(value), rest)

    [v.Tagged("Tail", v.Record(_)), ..rest] -> k(ir.Tail, rest)
    [v.Tagged("Cons", v.Record(_)), ..rest] -> k(ir.Cons, rest)

    [v.Tagged("Vacant", v.Record(_)), ..rest] -> k(ir.Vacant, rest)

    [v.Tagged("Empty", v.Record(_)), ..rest] -> k(ir.Empty, rest)
    [v.Tagged("Extend", v.String(label)), ..rest] -> k(ir.Extend(label), rest)
    [v.Tagged("Select", v.String(label)), ..rest] -> k(ir.Select(label), rest)
    [v.Tagged("Overwrite", v.String(label)), ..rest] ->
      k(ir.Overwrite(label), rest)
    [v.Tagged("Tag", v.String(label)), ..rest] -> k(ir.Tag(label), rest)
    [v.Tagged("Case", v.String(label)), ..rest] -> k(ir.Case(label), rest)
    [v.Tagged("NoCases", v.Record(_)), ..rest] -> k(ir.NoCases, rest)

    [v.Tagged("Perform", v.String(label)), ..rest] -> k(ir.Perform(label), rest)
    [v.Tagged("Handle", v.String(label)), ..rest] -> k(ir.Handle(label), rest)
    [v.Tagged("Builtin", v.String(identifier)), ..rest] ->
      k(ir.Builtin(identifier), rest)
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

pub fn do_decode_uri_component(term, _meta, env, k) {
  use unencoded <- result.then(cast.as_string(term))
  Ok(#(state.V(v.String(global.decode_uri_component(unencoded))), env, k))
}

pub fn encode_uri() {
  let type_ = t.Fun(t.Str, t.Open(-1), t.Str)
  #(type_, state.Arity1(do_encode_uri))
}

pub fn do_encode_uri(term, _meta, env, k) {
  use unencoded <- result.then(cast.as_string(term))
  Ok(#(state.V(v.String(global.encode_uri(unencoded))), env, k))
}

pub fn base64_encode() {
  let type_ = t.Fun(t.Str, t.Open(-1), t.Str)
  #(type_, state.Arity1(do_base64_encode))
}

pub fn do_base64_encode(term, _meta, env, k) {
  use unencoded <- result.then(cast.as_string(term))
  let value =
    v.String(gleam_string.replace(
      bit_array.base64_encode(bit_array.from_string(unencoded), True),
      "\r\n",
      "",
    ))
  Ok(#(state.V(value), env, k))
}

pub fn binary_from_integers() {
  let type_ = t.Fun(t.LinkedList(t.Integer), t.Open(-1), t.Binary)
  #(type_, builtin.binary_from_integers)
}
