import gleam/io
import gleam/list
import gleam/listx
import gleam/result
import gleam/set
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
    r.Function(arg, body, env) -> {
      // Note env list has variables multiple times and we need to find first only
      let env =
        list.filter_map(
          vars_used(body, [arg], set.new())
          |> set.to_list(),
          fn(var) {
            use term <- result.then(list.key_find(env, var))
            Ok(#(var, term))
          },
        )
      let env = flatten_env(env)
      // universal code from before
      // https://github.com/midas-framework/project_wisdom/pull/47/files#diff-a06143ff39109126525a296ab03fc419ba2d5da20aac75ca89477bebe9cf3fee
      // shake code
      // https://github.com/midas-framework/project_wisdom/pull/57/files#diff-d576d15df2bd35cb961bc2edd513c97027ef52ce19daf5d303f45bd11b327604
      let tail = e.Lambda(arg, body)
      // ordering by required is not the same as ordering by defined
      list.fold(env, tail, add_var)
    }
    r.Defunc(switch) -> capture_defunc(switch)
    r.Promise(_) ->
      panic("not capturing promise, yet. Can be done making serialize async")
  }
}

pub fn flatten_env(env) {
  do_flatten_env(list.reverse(env), [])
}

pub fn do_flatten_env(reversed, done) {
  case reversed {
    [] -> done
    [#(key, term), ..rest] -> {
      let done = [#(key, flatten_term(term, done)), ..done]
      do_flatten_env(rest, done)
    }
  }
}

pub fn flatten_term(exp, done) {
  case exp {
    r.Function(arg, body, env) -> {
      let env =
        list.filter(
          env,
          fn(x) {
            let #(var, value) = x
            case list.key_find(done, var) {
              Ok(v) if v == value -> False
              _ -> True
            }
          },
        )
      r.Function(arg, body, env)
    }

    r.LinkedList(items) -> {
      r.LinkedList(list.map(items, flatten_term(_, done)))
    }
    r.Tagged(key, exp) -> r.Tagged(key, flatten_term(exp, done))
    r.Record(fields) -> r.Record(listx.value_map(fields, flatten_term(_, done)))

    _ -> exp
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
    r.Shallow0(label) -> e.Shallow(label)
    r.Shallow1(label, handler) -> e.Apply(e.Shallow(label), capture(handler))
    r.Resume(label, handler, _resume) -> {
      // possibly we do nothing as the context of the handler has been lost
      // Resume needs to be an expression I think
      e.Apply(e.Handle(label), capture(handler))
      panic("not idea how to capture the func here, is it even possible")
    }
    r.Builtin(identifier, args) ->
      list.fold(
        args,
        e.Builtin(identifier),
        fn(exp, arg) { e.Apply(exp, capture(arg)) },
      )
  }
}

// env is the environment at this in a walk through the tree so these should not be added
fn vars_used(exp, env, found) {
  case exp {
    // This filter only works when built in functions are not renamed.
    e.Variable("ffi_" <> _) -> found
    e.Variable(v) ->
      case list.contains(env, v) {
        True -> found
        False -> set.insert(found, v)
      }
    e.Lambda(param, body) -> vars_used(body, [param, ..env], found)
    e.Apply(func, arg) -> {
      let found = vars_used(func, env, found)
      vars_used(arg, env, found)
    }
    // in recursive label also overwritten in value
    e.Let(label, value, then) -> {
      let found = vars_used(value, env, found)
      vars_used(then, [label, ..env], found)
    }
    _ -> found
  }
}
