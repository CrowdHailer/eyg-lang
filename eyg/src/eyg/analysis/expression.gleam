import gleam/option.{None, Option}

pub type Expression {
  Variable(label: String)
  Lambda(label: String, body: Expression)
  Apply(func: Expression, argument: Expression)
  Let(label: String, definition: Expression, body: Expression)

  // Primitive
  Integer
  Binary

  Vacant

  // Row
  Record(fields: List(#(String, Expression)), from: Option(String))
  Select(label: String)
  Tag(label: String)
  Match(
    value: Expression,
    branches: List(#(String, String, Expression)),
    tail: Option(#(String, Expression)),
  )

  // Effect
  // do/act/effect(effect is a verb and noun)
  Perform(label: String)
  Deep(variable: String, branches: List(#(String, String, String, Expression)))
}

pub const unit = Record([], None)
// Deep vs shallow
// arg vs computation taking unit
// single resumption or not
// block or function
// Does return value change

// Handle(comp, handled, return: Option)
// handle {

// } effect Log(msg), continue {
//   #(logs, value) = continue(#())
//   #([msg, logs], value)
// } return(value) {
//   #([], value)
// }

// Always do wrap in main

// handle {
//   #([], f())
// } effect Log(msg) continue {
//   #(logs, value) = replace(continue(Nil))
//   #([msg, logs], value)
// }

// choice
// handle {
//   [f()]
// } effect Random(Nil) continue {
//   append(continue(True), continue(False))
// }

// How do state

// let do_collect = match _ {
//   Log({msg, kont}) -> {
//     let #(logs, value) = handle(do_collect)([] -> kont(Ok))
//     #([msg, ..logs], value)
//   }
// }
// let collect_logs f -> {
//   handle({} -> #([], f({})))
// }

// // shallow
// let count current -> match _ {
//   Count(eff) -> {
//     handle(count(current + 1), [] -> kont(current))
//   }
// }

// // deep
// let count state match _ {
//   Count({kont}) -> #(current + 1, kont(current))
// }
// // single effect state different returns
// // Can this work without state or recursion No i assume
// let with_counter = handle state {
//   Inc _, continue -> #(state + 1, continue([]))
//   Get _, continue -> #(state, continue(state))
// }

// let from_zero = with_counter(0)
// let {state, result} = from_zero(_ -> {
//   let _ = do Inc
//   let _ = do Inc
//   do Get
// })

// // shallow
// let with_counter = fix(with_counter -> current -> handle {
//   Inc _, continue -> with_counter(current + 1, _ -> continue([]))
//   Get _, continue -> with_counter(current, _ -> continue(current))
// })(0)
// // TODO shallow inference

// let all_choice f -> handle state {
//   Random(Nil) cont -> #(state, append(cont(True), cont(False)))
// }(Nil)(_ -> [f()])

// let tracked_choice f -> handle state {
//   Random(Nil) cont -> {
//     let #(chosen, value) -> cont(True)
//     merge them all together
//     #(state, append(, cont(False)))
//   }
// }(Nil)(_ -> [[], f()])

// // deep
// let catch f -> handle _state {
//   Error reason, cont -> Fail(reason)
// }(Nil)(_ -> Ok(f()))

// // shallow
// let catch(f) -> handle {
//   Error reason, cont -> Fail(reason)
// }(_ -> Ok(f()))

// // let run = fix(effectful -> handle{})
// // shallow
// fn with_reader(dict) { 
//   let effectful = handle {
//     Read key, continue -> effectful(continue(map.get(key, or: "empty text")))
//   }
//   effectful(fn([]) {
//     l1 = Read("foo")
//     l2 = Read("bar")
//     l1 + l2
//   })
// }

// fn collect_logs(prog) {
//   let effectful = handle {
//     Log message, continue -> {
//       let #(log, value) = effectful(continue(Nil))
//       #([message, ..log]), value
//     }
//   }
//   // Pure exec need to return same type as effectful so the program to run needs wrapping in a anon fn that returns empty buffer and original value
//   let #(logs, value) = effectful(fn(Nil) { #([], prog(Nil)) })
//   print_all_logs(logs)
//   value
// }

// // Need fix + shallow or state i.e. deep
//   // no rec needed
// fn with_reader(words) { 
//   handle(state) {
//     Read key, continue -> continue(state, map.get(key, or: "empty text"))
//   }(words)
// }

// // This needs continuation in the effect types but allows state to be optional
// // continue can return a thunk
// fn with_reader(words) { 
//   let rec run = fn(state) handle {
//     Read key, continue -> run(state, continue(map.get(key, or: "empty text")))
//   }
//   run(words)
// }

// fn choose(prog) { 
//   // no rec needed
//   (handle(state) {
//     Random Nil, k -> append(k(state, True), k(state, False))
//   })(Nil)(Nil -> [prog(Nil)])
// }

// // state optional
// fn choose(prog) { 
//   // no rec needed
//   (handle {
//     Random _, cont -> append(cont(True), cont(False))
//   })(Nil -> [prog(Nil)])
// }

// fn choose(prog) {
//   let run = handle {
//     Random _, cont -> append(run(_ -> cont(True)), run(_ -> cont(False)))
//   }
//   run(_ -> [prog(Nil)])
// }

// // As not a thunk what's the order, do states keep building up correctly

// with_reader(fn([]) {
//   l1 = Read("foo")
//   l2 = Read("bar")
//   l1 + l2
// })

// // would need thunking of the exp value otherwise catching would behave different if variable or expression was used
// handle exp {
//   Effect
// }

// // curried
// let argified = fn(f, a) {
//   from_zero(_ -> f(a))
// }

// let capture = handle buffer {
//   Log message, continue -> #([message, ..buffer], continue(Ok))
//   // Does continuation have type return of #(extra, value)
//   // returned -> #([], continuation)
// }([])
// // Don't see how this joins together in choice example

// // it's not alway state threaded through if you have multiple resumptions

// // single effect means always same type in return
// // deep meens no recursion needed

// // Effects handlers can always be added with a mapping to the pure fn
// // TODO read koka paper
// // single label only but we need continuation etc
// // Handle with no label fn(fn(a, lslslsll, b), action) -> exec
// // Handle(label: String, param String, )  fn(a) -> <label x,y | eff>

// // handle {
// //   Log x, cont ->
// // }

// // need other syntaxes
// // // Needs a raise function that takes a union
// // handle(match {
// //   Log msg, k -> #(msg, k([]))
// //   Return value -> #("", value)
// //   other -> do(other)
// // })

// // // can I transpile all the row building into placeholders and application
// // // see heyleighs comment
// // Handle()
// // handle(Log)(Effect(msg, k) | Return value)(comp)(arg)
// // handle(Log)(fn(msg, k){}, fn(ret) {})(bob)
// // Case(Foo)(fn(x), fn(res))
