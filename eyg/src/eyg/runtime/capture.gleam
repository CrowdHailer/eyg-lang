import gleam/list
import gleam/result
import eygir/expression as e
import eyg/runtime/interpreter as r

fn add_var(exp, pair) {
  let #(label, value) = pair
  e.Let(label, capture(value), exp)
}

pub fn capture(term) {
  case term {
    r.Integer(value) -> e.Integer(value)
    r.Binary(value) -> e.Binary(value)
    r.LinkedList(items) ->
      list.fold_right(
        items,
        e.Tail,
        fn(tail, item) { e.Apply(e.Apply(e.Cons, capture(item)), tail) },
      )
    r.Record(fields) ->
      list.fold_right(
        fields,
        e.Empty,
        fn(record, pair) {
          let #(label, item) = pair
          e.Apply(e.Apply(e.Extend(label), capture(item)), record)
        },
      )
    r.Tagged(label, value) -> e.Apply(e.Tag(label), capture(value))
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
    r.Defunc(switch) -> capture_defunc(switch)
  }
}

fn capture_defunc(switch) {
  case switch {
    r.Cons0 -> e.Cons
    r.Cons1(item) -> e.Apply(e.Cons, capture(item))
    r.Extend0(label) -> e.Extend(label)
    r.Extend1(label, value) -> e.Apply(e.Extend(label), capture(value))
    r.Overwrite0(label) -> e.Overwrite(label)
    r.Overwrite1(label, value) -> e.Apply(e.Overwrite(label), capture(value))
    r.Select0(label) -> e.Select(label)
    r.Tag0(label) -> e.Tag(label)
    r.Match0(label) -> e.Case(label)
    r.Match1(label, value) -> e.Apply(e.Case(label), capture(value))
    r.Match2(label, value, matched) ->
      e.Apply(e.Apply(e.Case(label), capture(value)), capture(matched))
    r.NoCases0 -> e.NoCases
    r.Perform0(label) -> e.Perform(label)
    r.Handle0(label) -> e.Handle(label)
    r.Handle1(label, handler) -> e.Apply(e.Handle(label), capture(handler))
    r.Resume(label, handler, resume) ->
      // possibly we do nothing as the context of the handler has been lost
      todo("not idea how to capture the func here")
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
