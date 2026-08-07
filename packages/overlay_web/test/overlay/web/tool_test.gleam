// //// Might also be called run test

// // cache.loop is over the top when also using the looping in the run code
// // cache.loop
// // Is it infact much simpler to just go back to looping

// // Add NotFound to fetch status
// // cache.fetch_module() -> returns Working
// // NotFound includes a date
// /// Run could also be call or execute
// /// Will include eval/type
// /// A run type doesn't work because I end up wanting a workspace type wrapping a run for use in overlay work browser/editor

// // Tool calling context
// // pub type Context {
// //   Context(cache)
// // }

// // Need space for task_id

// pub type Meta =
//   List(Int)

// // fn do_run(calls, cache, continue, acc) {
// //   case calls {
// //     [] -> #(list.reverse(acc), cache, continue)
// //     [#(id, call), ..calls] -> {
// //       case call {
// //         _ -> {
// //           todo
// //         }
// //       }
// //       let #(call, cache, working) = loop(call, cache)
// //       let continue = working || continue
// //       let acc = [#(id, call), ..acc]
// //       do_run(calls, cache, continue, acc)
// //     }
// //   }
// // }

// // This is on browser
// fn external(effect: harness.Effect) -> browser.Effect(v.Value(a, b)) {
//   case effect {
//     harness.Alert(message) -> browser.Alert(message, fn() { v.unit() })
//     _ -> todo
//   }
// }
