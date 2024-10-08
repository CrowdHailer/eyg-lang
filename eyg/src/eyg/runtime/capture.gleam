import eyg/runtime/value as v
import eygir/annotated as a
import eygir/expression as e
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub fn capture(term) {
  // env is reversed with first needed deepest
  let #(exp, env) = do_capture(term, [])
  list.fold(env, exp, fn(then, definition) {
    let #(var, value) = definition
    e.Let(var, value, then)
  })
}

fn do_capture(term, env) {
  case term {
    v.Binary(value) -> #(e.Binary(value), env)
    v.Integer(value) -> #(e.Integer(value), env)
    v.Str(value) -> #(e.Str(value), env)
    v.LinkedList(items) ->
      list.fold_right(items, #(e.Tail, env), fn(state, item) {
        let #(tail, env) = state
        let #(item, env) = do_capture(item, env)
        let exp = e.Apply(e.Apply(e.Cons, item), tail)
        #(exp, env)
      })
    v.Record(fields) ->
      list.fold_right(fields, #(e.Empty, env), fn(state, pair) {
        let #(label, item) = pair
        let #(record, env) = state
        let #(item, env) = do_capture(item, env)
        let exp = e.Apply(e.Apply(e.Extend(label), item), record)
        #(exp, env)
      })
    v.Tagged(label, value) -> {
      let #(value, env) = do_capture(value, env)
      let exp = e.Apply(e.Tag(label), value)
      #(exp, env)
    }
    // universal code from before
    // https://github.com/midas-framework/project_wisdom/pull/47/files#diff-a06143ff39109126525a296ab03fc419ba2d5da20aac75ca89477bebe9cf3fee
    // shake code
    // https://github.com/midas-framework/project_wisdom/pull/57/files#diff-d576d15df2bd35cb961bc2edd513c97027ef52ce19daf5d303f45bd11b327604
    v.Closure(arg, body, captured) -> {
      // Note captured list has variables multiple times and we need to find first only
      let body = a.drop_annotation(body)
      let captured =
        list.filter_map(vars_used(body, [arg]), fn(var) {
          use term <- result.then(list.key_find(captured, var))
          Ok(#(var, term))
        })
      let #(env, wrapped) =
        list.fold(captured, #(env, []), fn(state, new) {
          let #(env, wrapped) = state
          let #(var, term) = new
          // This should also not capture the reused terms inside the env
          // could special rule std by passing in as an argument
          //
          let #(exp, env) = case var {
            // "std" -> #(e.Str("I AM STD"), env)
            _ -> do_capture(term, env)
          }
          case list.key_find(env, var) {
            Ok(old) if old == exp -> #(env, wrapped)
            // look for anything else matching the variable because then it might have already the expression
            Ok(_other) -> {
              let pre =
                list.filter(env, fn(e: #(String, _)) {
                  string.starts_with(e.0, string.append(var, "#")) && e.1 == exp
                })
              case pre {
                [] -> {
                  let scoped_var =
                    string.concat([var, "#", int.to_string(list.length(env))])
                  let assert Error(Nil) = list.key_find(env, scoped_var)
                  let wrapped = [#(scoped_var, var), ..wrapped]
                  let env = [#(scoped_var, exp), ..env]
                  #(env, wrapped)
                }
                [#(scoped_var, _)] -> #(env, [#(scoped_var, var), ..wrapped])
                _ -> panic as "assume only one existing"
              }
            }

            Error(Nil) -> #([#(var, exp), ..env], wrapped)
          }
        })

      let exp = e.Lambda(arg, body)
      let exp =
        list.fold(wrapped, exp, fn(exp, pair) {
          let #(scoped_var, var) = pair
          e.Let(var, e.Variable(scoped_var), exp)
        })
      #(exp, env)
    }
    v.Partial(switch, applied) -> capture_defunc(switch, applied, env)
    v.Promise(_) ->
      panic as "not capturing promise, yet. Can be done making serialize async"
  }
}

fn capture_defunc(switch, args, env) {
  let exp = case switch {
    v.Cons -> e.Cons
    v.Extend(label) -> e.Extend(label)
    v.Overwrite(label) -> e.Overwrite(label)
    v.Select(label) -> e.Select(label)
    v.Tag(label) -> e.Tag(label)
    v.Match(label) -> e.Case(label)
    v.NoCases -> e.NoCases
    v.Perform(label) -> e.Perform(label)
    v.Handle(label) -> e.Handle(label)
    v.Resume(_) -> {
      panic as "not idea how to capture the func here, is it even possible"
    }
    v.Shallow(label) -> e.Shallow(label)
    v.Builtin(identifier) -> e.Builtin(identifier)
  }

  list.fold(args, #(exp, env), fn(state, arg) {
    let #(exp, env) = state
    let #(arg, env) = do_capture(arg, env)
    let exp = e.Apply(exp, arg)
    #(exp, env)
  })
}

fn vars_used(exp, env) {
  list.reverse(do_vars_used(exp, env, []))
}

// env is the environment at this in a walk through the tree so these should not be added
fn do_vars_used(exp, env, found) {
  case exp {
    e.Variable(v) ->
      case !list.contains(env, v) && !list.contains(found, v) {
        True -> [v, ..found]
        False -> found
      }
    e.Lambda(param, body) -> do_vars_used(body, [param, ..env], found)
    e.Apply(func, arg) -> {
      let found = do_vars_used(func, env, found)
      do_vars_used(arg, env, found)
    }
    // in recursive label also overwritten in value
    e.Let(label, value, then) -> {
      let found = do_vars_used(value, env, found)
      do_vars_used(then, [label, ..env], found)
    }
    // everything else is simple, because first class, and will not add variables
    _ -> found
  }
}
