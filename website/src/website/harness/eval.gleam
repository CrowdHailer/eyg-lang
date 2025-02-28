import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/capture
import eyg/interpreter/cast
import eyg/interpreter/expression as r
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/option.{None, Some}
import gleam/result
import gleam/string

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

pub fn blocking(lift, k) {
  io.debug("evalling")
  use source <- result.map(cast.as_list(lift))
  promise.resolve(result_to_eyg(do(source, k)))
}

// TODO test error message works for eval
pub fn result_to_eyg(result) {
  case result {
    Ok(value) -> v.ok(value)
    Error(reason) -> v.error(v.String(string.inspect(reason)))
  }
}

// TODO test that effects are open
// This is the value to value
fn do(lift, k) {
  let src = language_to_expression(lift)
  io.debug(src)
  case src {
    Ok(src) ->
      case r.execute(src, []) {
        Ok(value) -> {
          let rest = k_to_func(k)
          let bindings = infer.new_state()
          let #(open_effect, bindings) = binding.mono(1, bindings)
          // TODO real refs
          let #(tree, bindings) =
            infer.infer(rest, open_effect, dict.new(), 0, bindings)
          let t = tree.1.1
          binding.resolve(t, bindings)
          io.debug(t)
          Ok(v.ok(value))
        }
        Error(_) -> panic as "Why this error"
      }
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
