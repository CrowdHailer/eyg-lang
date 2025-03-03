import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub fn capture(term, meta) {
  // env is reversed with first needed deepest
  let #(exp, env) = do_capture(term, [], meta)
  list.fold(env, exp, fn(then, definition) {
    let #(var, value) = definition
    #(ir.Let(var, value, then), meta)
  })
}

fn do_capture(term, env, meta) {
  case term {
    v.Binary(value) -> #(#(ir.Binary(value), meta), env)
    v.Integer(value) -> #(#(ir.Integer(value), meta), env)
    v.String(value) -> #(#(ir.String(value), meta), env)
    v.LinkedList(items) ->
      list.fold_right(items, #(#(ir.Tail, meta), env), fn(state, item) {
        let #(tail, env) = state
        let #(item, env) = do_capture(item, env, meta)
        let exp = #(
          ir.Apply(#(ir.Apply(#(ir.Cons, meta), item), meta), tail),
          meta,
        )
        #(exp, env)
      })
    v.Record(fields) ->
      list.fold_right(
        dict.to_list(fields),
        #(#(ir.Empty, meta), env),
        fn(state, pair) {
          let #(label, item) = pair
          let #(record, env) = state
          let #(item, env) = do_capture(item, env, meta)
          let exp = #(
            ir.Apply(#(ir.Apply(#(ir.Extend(label), meta), item), meta), record),
            meta,
          )
          #(exp, env)
        },
      )
    v.Tagged(label, value) -> {
      let #(value, env) = do_capture(value, env, meta)
      let exp = #(ir.Apply(#(ir.Tag(label), meta), value), meta)
      #(exp, env)
    }
    // universal code from before
    // https://github.com/midas-framework/project_wisdom/pull/47/files#diff-a06143ff39109126525a296ab03fc419ba2d5da20aac75ca89477bebe9cf3fee
    // shake code
    // https://github.com/midas-framework/project_wisdom/pull/57/files#diff-d576d15df2bd35cb961bc2edd513c97027ef52ce19daf5d303f45bd11b327604
    v.Closure(arg, body, captured) -> {
      let #(env, wrapped) =
        extract_used_env(vars_used(body, [arg]), env, meta, captured)
      let exp = #(ir.Lambda(arg, body), meta)
      let exp =
        list.fold(wrapped, exp, fn(exp, pair) {
          let #(scoped_var, var) = pair
          #(ir.Let(var, #(ir.Variable(scoped_var), meta), exp), meta)
        })
      #(exp, env)
    }
    v.Partial(switch, applied) -> capture_defunc(switch, applied, env, meta)
    v.Promise(_) ->
      panic as "not capturing promise, yet. Can be done making serialize async"
  }
}

fn extract_used_env(used, env, meta, captured) {
  // Note captured list has variables multiple times and we need to find first only
  let captured =
    list.filter_map(used, fn(var) {
      use term <- result.then(list.key_find(captured, var))
      Ok(#(var, term))
    })

  list.fold(captured, #(env, []), fn(state, new) {
    let #(env, wrapped) = state
    let #(var, term) = new
    // This should also not capture the reused terms inside the env
    // could special rule std by passing in as an argument
    //
    let #(exp, env) = case var {
      // "std" -> #(ir.String("I AM STD"), env)
      _ -> do_capture(term, env, meta)
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
}

fn capture_defunc(switch, args, env, meta) {
  let #(exp, env) = case switch {
    v.Cons -> #(#(ir.Cons, meta), env)
    v.Extend(label) -> #(#(ir.Extend(label), meta), env)
    v.Overwrite(label) -> #(#(ir.Overwrite(label), meta), env)
    v.Select(label) -> #(#(ir.Select(label), meta), env)
    v.Tag(label) -> #(#(ir.Tag(label), meta), env)
    v.Match(label) -> #(#(ir.Case(label), meta), env)
    v.NoCases -> #(#(ir.NoCases, meta), env)
    v.Perform(label) -> #(#(ir.Perform(label), meta), env)
    v.Handle(label) -> #(#(ir.Handle(label), meta), env)
    v.Resume(#(popped, captured)) -> {
      let stack = state.move(popped, state.Empty(dict.new()))
      do_capture_stack(stack, captured.scope, env, meta)
    }
    v.Builtin(identifier) -> #(#(ir.Builtin(identifier), meta), env)
  }
  list.fold(args, #(exp, env), fn(state, arg) {
    let #(exp, env) = state
    let #(arg, env) = do_capture(arg, env, meta)
    let exp = #(ir.Apply(exp, arg), meta)
    #(exp, env)
  })
}

// pub type Value(t) =
//   v.Value(t, #(List(#(istate.Kontinue(t), t)), istate.Env(t)))

// type Scope =
//   List(#(String, Value))

pub fn capture_stack(stack: state.Stack(t), captured: state.Env(t), meta: t) {
  // env is reversed with first needed deepest
  let #(exp, env) = do_capture_stack(stack, captured.scope, [], meta)
  list.fold(env, exp, fn(then, definition) {
    let #(var, value) = definition
    #(ir.Let(var, value, then), meta)
  })
}

fn do_capture_stack(
  stack: state.Stack(t),
  captured: List(_),
  env,
  meta: t,
) -> #(ir.Node(t), List(#(String, ir.Node(t)))) {
  let f = stack_to_func(stack, meta)
  let #(env, wrapped) = extract_used_env(vars_used(f, []), env, meta, captured)
  let exp =
    list.fold(wrapped, f, fn(exp, pair) {
      let #(scoped_var, var) = pair
      #(ir.Let(var, #(ir.Variable(scoped_var), meta), exp), meta)
    })
  #(exp, env)
}

pub fn stack_to_func(stack: state.Stack(t), meta: t) -> ir.Node(t) {
  do_stack_to_func(stack, meta, #(ir.Variable("magic"), meta))
}

fn do_stack_to_func(stack, meta: t, acc: ir.Node(t)) -> ir.Node(t) {
  case stack {
    state.Empty(_) -> #(ir.Lambda("magic", acc), meta)
    state.Stack(frame, meta, stack) -> {
      let acc = case frame {
        state.Assign(label, next, _env) -> #(ir.Let(label, acc, next), meta)
        state.Arg(arg, _env) -> #(ir.Apply(acc, arg), meta)
        state.Apply(func, _env) -> #(ir.Apply(capture(func, meta), acc), meta)
        state.CallWith(arg, _env) -> #(ir.Apply(acc, capture(arg, meta)), meta)
        state.Delimit(label, handler, _env, shallow) -> {
          let assert False = shallow
          #(
            ir.Apply(
              #(
                ir.Apply(#(ir.Handle(label), meta), capture(handler, meta)),
                meta,
              ),
              #(ir.Lambda("_", acc), meta),
            ),
            meta,
          )
          //  [
          // ])
        }
      }
      do_stack_to_func(stack, meta, acc)
    }
  }
}

fn vars_used(exp, env) {
  list.reverse(do_vars_used(exp, env, []))
}

// env is the environment at this in a walk through the tree so these should not be added
fn do_vars_used(tree, env, found) {
  let #(exp, _meta) = tree
  case exp {
    ir.Variable(v) ->
      case !list.contains(env, v) && !list.contains(found, v) {
        True -> [v, ..found]
        False -> found
      }
    ir.Lambda(param, body) -> do_vars_used(body, [param, ..env], found)
    ir.Apply(func, arg) -> {
      let found = do_vars_used(func, env, found)
      do_vars_used(arg, env, found)
    }
    // in recursive label also overwritten in value
    ir.Let(label, value, then) -> {
      let found = do_vars_used(value, env, found)
      do_vars_used(then, [label, ..env], found)
    }
    // everything else is simple, because first class, and will not add variables
    _ -> found
  }
}
