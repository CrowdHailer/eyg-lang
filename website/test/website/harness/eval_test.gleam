import eyg/interpreter/break
import eyg/interpreter/capture
import eyg/interpreter/cast
import eyg/interpreter/expression as r
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/io
import gleam/option.{None, Some}
import gleeunit/should

pub fn let_expression_test() {
  let assert Ok(source) =
    "{\"0\":\"l\",\"l\":\"source\",\"t\":{\"0\":\"a\",\"a\":{\"0\":\"v\",\"l\":\"source\"},\"f\":{\"0\":\"p\",\"l\":\"Eval\"}},\"v\":{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"ta\"},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"s\",\"v\":\"x\"},\"f\":{\"0\":\"t\",\"l\":\"Variable\"}},\"f\":{\"0\":\"c\"}}},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"i\",\"v\":81},\"f\":{\"0\":\"t\",\"l\":\"Integer\"}},\"f\":{\"0\":\"c\"}}},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"s\",\"v\":\"x\"},\"f\":{\"0\":\"t\",\"l\":\"Let\"}},\"f\":{\"0\":\"c\"}}}}"
    |> bit_array.from_string
    |> dag_json.from_block
  // ir.let_("x", ir.integer(81), ir.variable("x"))
  // ir.list([
  //   ir.tagged("Let", ir.string("x")),
  //   ir.tagged("Integer", ir.integer(81)),
  //   ir.tagged("Variable", ir.string("x")),
  // ])
  let #(reason, _, _, k) =
    r.execute(source, [])
    |> should.be_error
  let assert break.UnhandledEffect("Eval", lift) = reason
  lift
  |> should.equal(
    v.LinkedList([
      v.Tagged(label: "Let", value: v.String(value: "x")),
      v.Tagged(label: "Integer", value: v.Integer(value: 81)),
      v.Tagged(label: "Variable", value: v.String(value: "x")),
    ]),
  )

  let assert Ok(lift) = cast.as_list(lift)
  let assert Ok(_) = do(lift)

  k_to_func(k)
  |> io.debug
  v.Partial(v.Resume(k), [])
  |> capture.capture(Nil)
  |> io.debug
  todo
}

pub fn k_to_func(stack) {
  do_k_to_func(stack, ir.variable("magic"))
}

fn do_k_to_func(stack, acc) {
  case stack {
    state.Empty(_) -> ir.lambda("magic", acc)
    state.Stack(frame, meta, stack) -> {
      let acc = case frame {
        state.Assign(label, next, _env) -> ir.let_(label, acc, next)
        state.Arg(arg, _env) -> ir.apply(acc, arg)
        state.Apply(func, _env) -> ir.apply(capture.capture(func, Nil), acc)
        // TODO not tested this one
        state.CallWith(arg, _env) -> ir.apply(acc, capture.capture(arg, Nil))
        _ -> {
          io.debug(frame)
          todo as "I haven't the answer to this yet"
        }
      }
      do_k_to_func(stack, acc)
    }
  }
}

fn to_func(source) {
  let assert Error(#(reason, _meta, env, k)) = r.execute(source, [])
  let assert break.Vacant = reason
  k_to_func(k)
}

pub fn capure_continuation_test() {
  let source = ir.add(ir.vacant(), ir.integer(2))
  to_func(source)
  |> r.execute([])
  |> should.be_ok
  |> r.call([#(v.Integer(8), Nil)])
  |> should.be_ok
  |> should.equal(v.Integer(10))
}

// This is the value to value
fn do(lift) {
  let src = language_to_expression(lift)
  case src {
    Ok(src) -> r.execute(src, [])
    _ -> todo as "don't handle lift werror"
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
