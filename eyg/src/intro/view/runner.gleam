// // TODO rename as sidebar
// import eyg/interpreter/break
// import eyg/interpreter/value as v
// import gleam/http/request
// import gleam/int
// import gleam/list
// import gleam/option.{Some}
// import gleam/uri
// import intro/state
// import lustre/attribute as a
// import lustre/element.{none, text}
// import lustre/element/html as h
// import lustre/event as e
// import morph/lustre/components/key

// pub fn runner(state) {
//   let state.State(running: runner, document: guide, ..) = state

//   case guide.working, runner {
//     _, Some(#(ref, state.Runner(handle, effects))) ->
//       h.div(
//         [
//           a.class(
//             "bg-white bottom-8 fixed right-4 rounded top-4 w-1/3 shadow-xl border",
//           ),
//           a.style([#("left", "116ch")]),
//         ],
//         [
//           h.h1([a.class("text-right")], [
//             text("Running #" <> ref <> "   "),
//             h.button([e.on_click(state.CloseRunner)], [text("close")]),
//           ]),
//           logs1(list.reverse(effects)),
//           case handle {
//             state.Abort(#(reason, _, _, _)) ->
//               h.div([a.class("bg-red-300 p-10")], [
//                 text(break.reason_to_string(reason)),
//               ])
//             state.Suspended(state.TextInput(question, value), _env, _k) ->
//               h.div([a.class("border-4 border-green-500 px-6 py-2")], [
//                 h.div([], [text(question)]),
//                 h.form(
//                   [e.on_submit(state.Unsuspend(state.Asked(question, value)))],
//                   [
//                     h.input([
//                       a.class("border rounded"),
//                       a.value(value),
//                       e.on_input(fn(value) {
//                         state.UpdateSuspend(state.TextInput(question, value))
//                       }),
//                     ]),
//                   ],
//                 ),
//               ])
//             state.Suspended(state.Loading(reference), _, _) ->
//               h.div([a.class("border-4 border-gray-500 px-6 py-2")], [
//                 h.div([], [text("Loading: #" <> reference)]),
//               ])
//             state.Suspended(state.Awaiting(_), _, _) ->
//               h.div([a.class("border-4 border-gray-500 px-6 py-2")], [
//                 h.div([], [text("Awaiting: ")]),
//               ])
//             state.Suspended(state.Timer(remaining), _, _) ->
//               h.div([a.class("border-4 border-blue-500 px-6 py-2")], [
//                 h.div([], [text("Waiting " <> int.to_string(remaining))]),
//               ])
//             state.Suspended(state.Geo, _, _) ->
//               h.div([a.class("border-4 border-blue-500 px-6 py-2")], [
//                 h.div([], [text("Finding location ")]),
//               ])
//             state.Done(value) ->
//               h.div([a.class("border-4 border-green-500 px-6 py-2")], [
//                 h.div([], [text("Done")]),
//                 h.div([], [text(old_value.debug(value))]),
//               ])
//             // _ -> text()
//           },
//         ],
//       )
//     state.Working(_), _ ->
//       h.div(
//         [
//           a.class(
//             "bg-white bottom-8 fixed right-4 rounded top-4 w-1/3 shadow-xl border",
//           ),
//           a.style([#("left", "116ch")]),
//         ],
//         [
//           h.div([a.class("p-2 font-mono vstack")], [
//             h.h1([a.class("text-xl font-bold cover")], [text("commands")]),
//             h.div([a.class("cover")], [key.render()]),
//           ]),
//         ],
//       )
//     _, _ -> none()
//   }
// }

// fn logs1(logs) {
//   h.div(
//     [
//       a.style([
//         #("display", "grid"),
//         #("grid-template-columns", "minmax(8ch, auto) 1fr"),
//       ]),
//     ],
//     list.flat_map(logs, fn(effect) {
//       case effect {
//         state.Log(message) -> [
//           h.span([a.class("bg-gray-700 text-white text-right px-2")], [
//             text("Log"),
//           ]),
//           h.span([a.class("px-1")], [text(message)]),
//         ]
//         state.Waited(time) -> [
//           h.span([a.class("bg-blue-700 text-white text-right px-2")], [
//             text("Wait"),
//           ]),
//           h.span([a.class("px-1")], [text(int.to_string(time))]),
//         ]
//         state.Awaited(_value) -> [
//           h.span([a.class("bg-gray-700 text-white text-right px-2")], [
//             text("Awaited"),
//           ]),
//           h.span([a.class("px-1")], []),
//         ]
//         state.Geolocation(_) -> [
//           h.span([a.class("bg-blue-700 text-white text-right px-2")], [
//             text("Geo"),
//           ]),
//           h.span([a.class("px-1")], []),
//         ]
//         state.Asked(question, answer) -> [
//           h.span([a.class("bg-gray-700 text-white text-right px-2")], [
//             text("Ask"),
//           ]),
//           h.span([a.class("px-1")], [text(question), text(": "), text(answer)]),
//         ]
//         state.Fetched(request) -> [
//           h.span([a.class("bg-gray-700 text-white text-right px-2")], [
//             text("Fetched"),
//           ]),
//           h.span([a.class("px-1")], [
//             text(uri.to_string(request.to_uri(request))),
//           ]),
//         ]
//       }
//     }),
//   )
// }
