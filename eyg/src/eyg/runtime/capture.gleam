import gleam/io
import gleam/list
import gleam/listx
import gleam/result
import gleam/set
import eygir/expression as e
import eyg/runtime/interpreter as r

pub fn capture(term) {
  // env is reversed with first needed deepest
  let #(exp, env) = do_capture(term, [])
  exp
  list.fold(
    env,
    exp,
    fn(then, definition) {
      let #(var, value) = definition
      e.Let(var, value, then)
    },
  )
}

fn do_capture(term, env) {
  case term {
    r.Integer(value) -> #(e.Integer(value), env)
    r.Binary(value) -> #(e.Binary(value), env)
    r.LinkedList(items) ->
      list.fold_right(
        items,
        #(e.Tail, env),
        fn(state, item) {
          let #(tail, env) = state
          let #(item, env) = do_capture(item, env)
          let exp = e.Apply(e.Apply(e.Cons, item), tail)
          #(exp, env)
        },
      )
    r.Record(fields) ->
      list.fold_right(
        fields,
        #(e.Empty, env),
        fn(state, pair) {
          let #(label, item) = pair
          let #(record, env) = state
          let #(item, env) = do_capture(item, env)
          let exp = e.Apply(e.Apply(e.Extend(label), item), record)
          #(exp, env)
        },
      )
    r.Tagged(label, value) -> {
      let #(value, env) = do_capture(value, env)
      let exp = e.Apply(e.Tag(label), value)
      #(exp, env)
    }
    // universal code from before
    // https://github.com/midas-framework/project_wisdom/pull/47/files#diff-a06143ff39109126525a296ab03fc419ba2d5da20aac75ca89477bebe9cf3fee
    // shake code
    // https://github.com/midas-framework/project_wisdom/pull/57/files#diff-d576d15df2bd35cb961bc2edd513c97027ef52ce19daf5d303f45bd11b327604
    r.Function(arg, body, captured) -> {
      // Note captured list has variables multiple times and we need to find first only
      let captured =
        list.filter_map(
          vars_used(body, [arg]),
          fn(var) {
            use term <- result.then(list.key_find(captured, var))
            Ok(#(var, term))
          },
        )
      let env =
        list.fold(
          captured,
          env,
          fn(env, new) {
            let #(var, term) = new
            let #(exp, env) = do_capture(term, env)
            case list.key_find(env, var) {
              Ok(_) -> todo
              Error(Nil) -> [#(var, exp), ..env]
            }
          },
        )

      let exp = e.Lambda(arg, body)
      #(exp, env)
    }
    r.Defunc(switch) -> capture_defunc(switch, env)
    r.Promise(_) ->
      panic("not capturing promise, yet. Can be done making serialize async")
  }
}

fn capture_defunc(switch, env) {
  case switch {
    r.Cons0 -> #(e.Cons, env)
    r.Cons1(item) -> {
      let #(item, env) = do_capture(item, env)
      let exp = e.Apply(e.Cons, item)
      #(exp, env)
    }
    r.Extend0(label) -> #(e.Extend(label), env)
    r.Extend1(label, value) -> {
      let #(value, env) = do_capture(value, env)
      let exp = e.Apply(e.Extend(label), value)
      #(exp, env)
    }
    r.Overwrite0(label) -> #(e.Overwrite(label), env)
    r.Overwrite1(label, value) -> {
      let #(value, env) = do_capture(value, env)
      let exp = e.Apply(e.Overwrite(label), value)
      #(exp, env)
    }
    r.Select0(label) -> #(e.Select(label), env)
    r.Tag0(label) -> #(e.Tag(label), env)
    r.Match0(label) -> #(e.Case(label), env)
    r.Match1(label, value) -> {
      let #(value, env) = do_capture(value, env)
      let exp = e.Apply(e.Case(label), value)
      #(exp, env)
    }
    r.Match2(label, value, matched) -> {
      let #(value, env) = do_capture(value, env)
      let #(matched, env) = do_capture(matched, env)
      let exp = e.Apply(e.Apply(e.Case(label), value), matched)
      #(exp, env)
    }
    r.NoCases0 -> #(e.NoCases, env)
    r.Perform0(label) -> #(e.Perform(label), env)
    r.Handle0(label) -> #(e.Handle(label), env)
    r.Handle1(label, handler) -> {
      let #(handler, env) = do_capture(handler, env)
      let exp = e.Apply(e.Handle(label), handler)
      #(exp, env)
    }
    r.Resume(label, handler, _resume) -> {
      // possibly we do nothing as the context of the handler has been lost
      // Resume needs to be an expression I think
      let #(handler, env) = do_capture(handler, env)

      let exp = e.Apply(e.Handle(label), handler)
      #(exp, env)
      panic("not idea how to capture the func here, is it even possible")
    }
    r.Shallow0(label) -> #(e.Shallow(label), env)
    r.Shallow1(label, handler) -> {
      let #(handler, env) = do_capture(handler, env)
      let exp = e.Apply(e.Shallow(label), handler)
      #(exp, env)
    }
    r.ShallowResume(_resume) -> {
      // possibly we do nothing as the context of the handler has been lost
      // Resume needs to be an expression I think
      panic(
        "not idea how to capture the func here, is it even possible: shallow",
      )
    }
    r.Builtin(identifier, args) ->
      list.fold(
        args,
        #(e.Builtin(identifier), env),
        fn(state, arg) {
          let #(exp, env) = state
          let #(arg, env) = do_capture(arg, env)
          let exp = e.Apply(exp, arg)
          #(exp, env)
        },
      )
  }
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
// Duplicate needed name
// fn capture(term, env) {
//   case term {
//     r.LinkedList(items) ->
//       list.fold_right(
//         items,
//         #(e.Tail, env),
//         fn(state, item) {
//           let #(tail, env) = state
//           let #(item, env) = capture(item, env)
//           let exp = e.Apply(e.Apply(e.Cons, item), tail)
//           #(exp, env)
//         },
//       )
//     r.Function(param, body, captured) -> {
//       // capture.vars_used(body, [param], set.new())
//       let #(r.Function(param, body, []), env) =
//         capture_fn(param, body, captured, env)
//       #(e.Lambda(param, body), env)
//     }
//     _ -> todo("cp")
//   }
// }

// fn capture_fn(param, body, captured, env) -> #(r.Term, _) {
//   let captured =
//     list.filter_map(
//       // Should I capture in order used
//       capture.vars_used(body, [param], set.new())
//       |> set.to_list(),
//       fn(var) {
//         use term <- result.then(list.key_find(captured, var))
//         Ok(#(var, term))
//       },
//     )

//   let env =
//     list.fold(
//       captured,
//       env,
//       fn(env, item) {
//         let #(var, value) = item
//         case list.key_find(env, var) {
//           // first order keys in the map then render to prevent dedupe. but if same value already equal
//           Ok(v) if v == value -> env
//           Ok(_) -> todo("conflict")
//           Error(Nil) ->
//             case value {
//               r.Function(param, body, captured) -> {
//                 let #(value, env) = capture_fn(param, body, captured, env)
//                 [#(var, value), ..env]
//               }
//               _ -> [item, ..env]
//             }
//         }
//       },
//     )
//   #(r.Function(param, body, []), env)
// }

// // Test top level var shadowing
// // Test nested shadowing

// // let a = 1
// // let a = huge
// // let f1 _ -> a
// // let f2 _ -> f

// // pub fn double_catch_test() {
// //   let exp =
// //     e.Let(
// //       "std",
// //       e.Binary("Standard"),
// //       e.Let(
// //         "f0",
// //         e.Lambda("_", e.Variable("std")),
// //         e.Let(
// //           "f1",
// //           e.Lambda("_", e.Variable("f0")),
// //           e.Let(
// //             "f2",
// //             e.Lambda("_", e.Variable("std")),
// //             e.list([e.Variable("f1"), e.Variable("f2")]),
// //           ),
// //         ),
// //       ),
// //     )
// //   let assert r.Value(term) = r.eval(exp, env.empty(), r.Value)
// //   io.debug(term)
// //   io.debug("============")
// //   let #(exp, env) = capture(term, [])
// //   exp
// //   |> io.debug
// //   env
// //   |> io.debug

// //   todo
// // }

// // let a = 3
// // let f1 = _ -> a
// // let a = 5
// // let f2 = _ -> a
// // [f1,f2]
// // // hash runtime

// // let x = 1
// // let y = _ -> x
// // _ -> [x,y]
