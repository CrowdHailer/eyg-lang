import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/unify
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
import morph/analysis

pub const l = "Eval"

pub fn lift() {
  t.ast()
}

pub fn reply() {
  t.result(t.Var(0), t.String)
}

pub fn type_() {
  #(l, #(lift(), reply()))
}

pub fn blocking(lift: state.Value(t), meta, env: state.Env(t), k) {
  io.debug("evalling")
  use source <- result.map(cast.as_list(lift))
  promise.resolve(result_to_eyg(do(source, meta, env, k)))
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
fn do(lift, meta, env: state.Env(t), k) {
  case language_to_expression(lift) {
    Ok(src) ->
      case r.execute(src, []) {
        Ok(value) -> {
          let rest = capture.capture_stack(k, env, meta)
          let bindings = infer.new_state()
          let #(open_effect, bindings) = binding.mono(1, bindings)
          // TODO real refs
          let #(tree, bindings) =
            infer.infer(rest, open_effect, dict.new(), 0, bindings)
          // This is the function type
          let t = tree.1.1
          binding.resolve(t, bindings)
          io.debug(t)
          let #(got, bindings) = analysis.value_to_type(value, bindings, meta)
          let #(got, bindings) = binding.instantiate(got, 1, bindings)

          let #(ty_ret, bindings) = binding.mono(1, bindings)
          let #(test_eff, bindings) = binding.mono(1, bindings)

          case
            unify.unify(
              t.Fun(t.result(got, t.String), test_eff, ty_ret),
              t,
              1,
              bindings,
            )
          {
            Ok(_) -> Ok(value)
            Error(reason) -> {
              Error(debug.render_reason(reason))
            }
          }
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
