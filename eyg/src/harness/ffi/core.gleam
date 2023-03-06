import gleam/list
import gleam/result
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/spec.{
  build, empty, end, lambda, record, string, unbound, union, variant,
}
import eygir/expression as e
import eygir/encode

pub const true = r.Tagged("True", r.Record([]))

pub const false = r.Tagged("False", r.Record([]))

pub fn equal() {
  let el = unbound()
  lambda(
    el,
    lambda(
      el,
      union(variant(
        "True",
        record(empty()),
        variant("False", record(empty()), end()),
      )),
    ),
  )
  |> build(fn(x) {
    fn(y) {
      fn(true) {
        fn(false) {
          case x == y {
            True -> true(Nil)
            False -> false(Nil)
          }
        }
      }
    }
  })
}

pub fn debug() {
  lambda(unbound(), string())
  |> build(r.to_string)
}

fn fixed(builder) {
  r.Builtin(fn(arg, inner_k) {
    r.eval_call(builder, fixed(builder), r.eval_call(_, arg, inner_k))
  })
}

pub fn fix() {
  let typ =
    t.Fun(
      t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-1)),
      t.Open(-3),
      t.Unbound(-1),
    )

  let value =
    r.Builtin(fn(builder, k) { r.eval_call(builder, fixed(builder), k) })
  #(typ, value)
}

// THis should be replaced by capture which returns ast
pub fn serialize() {
  let typ =
    t.Fun(t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-2)), t.Open(-3), t.Binary)

  let value =
    r.Builtin(fn(builder, k) {
      let exp = runtime_to_ast(builder)
      r.continue(k, r.Binary(encode.to_json(exp)))
    })
  #(typ, value)
}

fn add_var(exp, pair) {
  let #(label, value) = pair
  e.Let(label, runtime_to_ast(value), exp)
}

fn runtime_to_ast(term) {
  case term {
    r.Integer(value) -> e.Integer(value)
    r.Binary(value) -> e.Binary(value)
    r.LinkedList(items) ->
      list.fold_right(
        items,
        e.Tail,
        fn(tail, item) { e.Apply(e.Apply(e.Cons, runtime_to_ast(item)), tail) },
      )
    r.Record(fields) ->
      list.fold_right(
        fields,
        e.Empty,
        fn(record, pair) {
          let #(label, item) = pair
          e.Apply(e.Apply(e.Extend(label), runtime_to_ast(item)), record)
        },
      )
    r.Tagged(label, value) -> e.Apply(e.Tag(label), runtime_to_ast(value))
    r.Builtin(_) -> e.Binary("builtin function")
    r.Function(arg, body, env) -> {
      // Note env list has variables multiple times and we need to find first only
      let assert Ok(env) =
        list.try_map(
          vars_used(body, [arg]),
          fn(var) {
            use term <- result.then(list.key_find(env, var))
            Ok(#(var, term))
          },
        )
      // universal code from before
      // https://github.com/midas-framework/project_wisdom/pull/47/files#diff-a06143ff39109126525a296ab03fc419ba2d5da20aac75ca89477bebe9cf3fee
      // shake code
      // https://github.com/midas-framework/project_wisdom/pull/57/files#diff-d576d15df2bd35cb961bc2edd513c97027ef52ce19daf5d303f45bd11b327604
      let tail = e.Lambda(arg, body)
      // ordering by required is not the same as ordering by defined
      list.fold(env, tail, add_var)
    }
  }
}

fn vars_used(exp, env) {
  case exp {
    // This filter only works when built in functions are not renamed.
    e.Variable("ffi_" <> _) -> []
    e.Variable(v) ->
      case list.contains(env, v) {
        True -> []
        False -> [v]
      }
    e.Lambda(param, body) -> vars_used(body, [param, ..env])
    e.Apply(func, arg) -> list.append(vars_used(func, env), vars_used(arg, env))
    // in recursive label also overwritten in value
    e.Let(label, value, then) ->
      list.append(vars_used(value, env), vars_used(then, [label, ..env]))
    _ -> []
  }
}
