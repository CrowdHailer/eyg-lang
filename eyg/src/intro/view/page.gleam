// import eyg/analysis/type_/binding/debug
// import eyg/analysis/type_/isomorphic as t
// import eyg/document/section
// import eyg/package
// import eyg/parse/lexer
// import eyg/interpreter/value as v
// import website/sync/sync
// import eyg/text/highlight
// import eyg/text/text
// import gleam/dict
// import gleam/dynamic
// import gleam/dynamicx
// import gleam/int
// import gleam/io
// import gleam/list
// import gleam/option.{None, Some}
// import gleam/pair
// import gleam/string
// import intro/state
// import intro/view/background
// import intro/view/runner
// import lustre/attribute as a
// import lustre/element.{fragment, map as element_map, none, text} as lelement
// import lustre/element/html as h
// import lustre/event as e
// import morph/analysis
// import morph/buffer
// import morph/lustre/frame
// import morph/lustre/render
// import morph/picker
// import plinth/browser/document
// import plinth/browser/element
// import plinth/browser/event
// import plinth/browser/window

// pub fn render(state) {
//   h.div([a.class("relative min-h-screen")], [
//     h.div(
//       [
//         a.class("fixed top-0 bottom-0 left-0 right-0"),
//         a.attribute("dangerous-unescaped-html", background.lime_splash),
//       ],
//       [],
//     ),
//     content(state),
//     runner.runner(state),
//   ])
// }

// pub fn content(state) {
//   let state.State(document: document, cache: cache, ..) = state
//   let #(public, hash) = case document.working {
//     state.Complete(public, hash) -> #(public, hash)
//     _ -> #([], "")
//   }
//   // TODO need total missing
//   let loading = sync.missing(cache, [])
//   h.div([a.class("relative vstack")], [
//     h.div([a.class("cover expand")], [
//       h.h1([a.class("p-4 text-6xl")], [text("Eyg")]),
//       h.div(
//         [
//           a.class(" "),
//           e.on_click(state.Blur),
//           a.style([
//             #("display", "grid"),
//             #("grid-template-columns", "8em 100ch"),
//           ]),
//         ],
//         [
//           h.div([], []),
//           h.div([a.class("bg-gray-200 bg-opacity-70 p-2 rounded border")], [
//             h.div([], [
//               h.span([a.class("font-bold")], [text("public: ")]),
//               ..list.map(list.intersperse(public, ", "), text)
//             ]),
//             h.div([a.class("")], [
//               h.span([a.class("font-bold")], [text("hash: ")]),
//               text(hash),
//             ]),
//           ]),
//         ],
//       ),
//       h.div(
//         [
//           a.class(" "),
//           a.style([
//             #("display", "grid"),
//             #("grid-template-columns", "8em 100ch"),
//           ]),
//         ],
//         list.flat_map(loading, fn(loading) {
//           [
//             h.div([], []),
//             h.div([a.class("bg-gray-200 bg-opacity-70 p-2 rounded")], [
//               text("loading "),
//               text(loading),
//               text("..."),
//             ]),
//           ]
//         }),
//       ),
//       ..sections(document, cache)
//     ]),
//   ])
// }

// fn sections(document, references) {
//   let state.Guide(before, focus) = document
//   let before = list.reverse(before)

//   let before = list.index_map(before, fn(s, i) { section(s, i, references) })
//   let focus_and_after = case focus {
//     state.Complete(_, _) -> []
//     state.Working(state.Focus(scope, comments, buffer, after)) -> {
//       let #(projection, mode) = buffer
//       let a = state.analyse(projection, scope, references)
//       let errors = analysis.type_errors(a)
//       let t = analysis.do_type_at(a, projection)
//       let targets = []
//       let offset = list.length(before) + 1
//       [
//         h.div(
//           [
//             a.class("mx-auto"),
//             a.style([
//               #("display", "grid"),
//               #("grid-template-columns", "8em 100ch 1fr"),
//             ]),
//           ],
//           list.append(context_section(comments), [
//             h.div([a.class("my-4 p-2 text-right")], targets),
//             h.div(
//               [
//                 a.class(
//                   "my-4 bg-gray-200 rounded bg-opacity-70 border font-mono outline-none overflow-hidden",
//                 ),
//                 a.attribute("tabindex", "0"),
//                 a.id("code"),
//                 e.on_keydown(state.KeyDown),
//                 // on blur doesn't work because we blur into the edit text and integer inputs
//               // e.on_blur(state.Blur),
//               ],
//               [
//                 h.div([a.class("p-2 whitespace-nowrap overflow-auto")], [
//                   render.projection(projection, False),
//                 ]),
//                 case t {
//                   Ok(t.Var(_)) -> none()
//                   Ok(t) ->
//                     h.div([a.class("px-2 py-1 -mt-1")], [text(debug.mono(t))])
//                   Error(Nil) -> none()
//                 },
//                 text("show pallet again"),
//                 // case mode {
//               //   buffer.Command(None) -> render_errors(errors)
//               //   buffer.Command(Some(failure)) ->
//               //     h.div([a.class("px-2 py-1 -mt-1")], [
//               //       text(fail_message(failure)),
//               //     ])
//               //   buffer.EditInteger(i, _rebuild) ->
//               //     h.div([a.class("px-2 py-1 -mt-1")], [
//               //       pallet.integer_input(i) |> element_map(state.Buffer),
//               //     ])
//               //   buffer.EditText(text, _rebuild) ->
//               //     h.div([a.class("px-2 py-1 -mt-1")], [
//               //       pallet.string_input(text) |> element_map(state.Buffer),
//               //     ])
//               //   buffer.Pick(picker, _) ->
//               //     h.div([a.class("px-2 py-1 -mt-1")], [
//               //       picker.render(picker) |> lelement.map(state.UpdatePicker),
//               //     ])
//               // },
//               ],
//             ),
//             h.div([a.class("p-2")], []),
//           ]),
//         ),
//         ..list.index_map(after, fn(s, i) { section(s, i + offset, references) })
//       ]
//     }
//   }
//   list.append(before, focus_and_after)
// }

// fn fail_message(reason) {
//   case reason {
//     buffer.NoKeyBinding(key) ->
//       string.concat(["No action bound for key '", key, "'"])
//     buffer.ActionFailed(action) ->
//       string.concat(["Action ", action, " not possible at this position"])
//   }
// }

// fn render_errors(errors) {
//   case errors {
//     // [] -> h.div([a.class("sticky bottom-0 px-2 py-1 text-white")], [])
//     [] -> none()
//     _ ->
//       h.div(
//         [a.class("sticky bottom-0 px-2 py-1 -mt-1 orange-gradient text-white")],
//         list.map(errors, fn(error) {
//           let #(path, reason) = error
//           h.div([a.class("")], [text(debug.reason(reason))])
//         }),
//       )
//   }
// }

// fn context_section(context) {
//   list.flat_map(context, fn(comment) {
//     [
//       h.div([a.style([#("align-self", "bottom")])], []),
//       h.div([a.class("bg-white bg-opacity-70 rounded")], [text(comment)]),
//       h.div([], []),
//     ]
//   })
// }

// fn do_targets(pairs, acc, values) {
//   case pairs {
//     [] -> list.reverse(acc)
//     [#(#(pattern, value), reference), ..pairs] -> {
//       // render.assign(pattern, value)

//       let height =
//         render.expression(value)
//         |> frame.line_height

//       let first = case dict.get(values, reference) {
//         Ok(v.Closure(_, _, _)) ->
//           h.button(
//             [
//               a.class("bg-red-400 text-white px-2 -mr-2 rounded-l"),
//               e.on_click(state.Run(reference)),
//             ],
//             [text("Run >")],
//           )
//         Ok(_) ->
//           h.span(
//             [
//               a.class(
//                 "bg-blue-400 text-white px-2 -mr-2 inline-block rounded-l font-mono",
//               ),
//             ],
//             [text("#"), text(reference)],
//           )
//         Error(Nil) -> h.p([], [text("couldnt find: " <> reference)])
//       }

//       let acc = [first, ..acc]
//       let padding = list.repeat(h.br([]), height)
//       let acc = list.append(padding, acc)
//       do_targets(pairs, acc, values)
//     }
//   }
// }

// fn targets(section, cache) {
//   let package.Section(content, computed) = section
//   // probably part of package section
//   let section.Section(_context, snippet) = content

//   let assert Ok(pairs) = list.strict_zip(snippet, computed.references)

//   do_targets(pairs, [], sync.values(cache))
// }

// fn section(section, index, references) {
//   let package.Section(content, computed) = section
//   // probably part of package section
//   let section.Section(context, snippet) = content

//   let targets = targets(section, references)

//   h.div(
//     [
//       a.class("mx-auto"),
//       a.style([
//         #("display", "grid"),
//         #("grid-template-columns", "8em 100ch 1fr"),
//       ]),
//     ],
//     list.append(context_section(context), [
//       // h.div([a.class("my-4 p-2 text-right")], []),
//       h.div([a.class("my-4 p-2 text-right")], targets),
//       h.div(
//         [
//           a.class("my-4 bg-gray-200 rounded bg-opacity-70 border font-mono"),
//           e.on_click(state.FocusOnSnippet(index)),
//           a.attribute("tabindex", "0"),
//         ],
//         [
//           h.div(
//             [a.class("p-2 whitespace-nowrap overflow-auto")],
//             render.assigns(snippet),
//           ),
//           render_errors(computed.errors),
//         ],
//       ),
//       h.div([a.class("p-2")], []),
//     ]),
//   )
// }

// // TODO this old section has the text goodness
// // fn section(section, index, references: references.Store(_)) {

// //   let on_update = fn(new) { state.EditCode(index, new) }

// //   let errors = case snippet {
// //     snippet.Processed(errors: errors, ..) ->
// //       errors
// //       |> list.map(fn(error) { #(debug.reason(error.0), error.1) })
// //     // Error(reason) -> {
// //     //   let end = case source {
// //     //     snippet.Text(code) -> string.byte_size(code)
// //     //     _ -> 0
// //     //   }
// //     //   let #(message, start) = case reason {
// //     //     parser.UnexpectedToken(position: position, token: token) -> {
// //     //       #("Unexpected code token: " <> string.inspect(token), position)
// //     //     }
// //     //     parser.UnexpectEnd -> #("Code is unfinished", end)
// //     //   }
// //     //   [#(message, #(start, end))]
// //     // }
// //   }
// //   let #(error_messages, error_spans) = list.unzip(errors)

// //   let targets = case snippet {
// //     snippet.Processed(assignments: assignments, ..) -> {
// //       io.debug(assignments)
// //       let #(_, pushed) =
// //         // lines are 1 indexed probably worth Fixing TODO?
// //         list.fold(assignments, #(1, []), fn(acc, assignment) {
// //           let #(next, pushed) = acc
// //           case assignment {
// //             #(line, Ok(ref)) if line >= next -> {
// //               case dict.get(references.types, ref) {
// //                 Ok(t.Fun(_, _, _)) -> {
// //                   // io.debug(x)
// //                   let padding = list.repeat(h.br([]), line - next)
// //                   let pushed = list.append(padding, pushed)
// //                   let el =
// //                     h.button(
// //                       [
// //                         a.class("bg-red-400 text-white px-2 -mr-2 rounded-l"),
// //                         e.on_click(state.Run(ref)),
// //                       ],
// //                       [text("Run >")],
// //                     )
// //                   #(line + 1, [h.br([]), el, ..pushed])
// //                 }
// //                 _ -> acc
// //               }
// //             }
// //             _ -> acc
// //           }
// //         })
// //       list.reverse(pushed)
// //     }
// //   }

// //   h.div(
// //     [
// //       a.class("mx-auto"),
// //       a.style([
// //         #("display", "grid"),
// //         #("grid-template-columns", "8em 100ch 1fr"),
// //       ]),
// //     ],
// //     list.append(context_section(context), case source {
// //       snippet.Text(code) -> {
// //         [
// //           h.div([a.class("my-4 p-2 text-right")], targets),
// //           h.div([a.class("my-4 bg-gray-200 rounded bg-opacity-70")], [
// //             h.div([a.class("p-2")], [text_input(code, on_update, error_spans)]),
// //             h.div(
// //               [a.class("sticky bottom-0")],
// //               list.map(error_messages, fn(message) {
// //                 h.div(
// //                   [a.class("px-2 -mt-1 py-1 rounded bg-pink-500 text-white")],
// //                   [text(message)],
// //                 )
// //               }),
// //             ),
// //           ]),
// //           h.div([], []),
// //         ]
// //       }
// //       snippet.Structured(exp) -> {
// //         [
// //           // h.div([a.class("my-4 p-2 text-right")], []),
// //           h.div([a.class("my-4 p-2 text-right")], targets),
// //           // TODO remove case
// //           h.div(
// //             [
// //               a.class(
// //                 "my-4 bg-gray-200 rounded bg-opacity-70 p-2 border font-mono",
// //               ),
// //               e.on_click(state.FocusOnSnippet(index)),
// //               a.attribute("tabindex", "0"),
// //             ],
// //             render.assigns(editable.open_assignments(exp)),
// //           ),
// //           h.div([a.class("p-2")], []),
// //         ]
// //       }
// //     }),
// //   )
// // }

// const monospace = "ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,\"Liberation Mono\",\"Courier New\",monospace"

// const pre_id = "highlighting-underlay"

// fn text_input(code, on_update, error_spans) {
//   let error_spans = separate_spans(error_spans)
//   h.div(
//     [
//       a.style([
//         #("position", "relative"),
//         #("font-family", monospace),
//         #("width", "100%"),
//         // #("height", "100%"),

//         #("overflow", "hidden"),
//       ]),
//     ],
//     [
//       h.pre(
//         [
//           a.id(pre_id),
//           a.style([
//             #("position", "absolute"),
//             #("top", "0"),
//             #("bottom", "0"),
//             #("left", "0"),
//             #("right", "0"),
//             #("margin", "0 !important"),
//             #("white-space", "pre-wrap"),
//             #("word-wrap", "break-word"),
//             #("overflow", "auto"),
//           ]),
//         ],
//         highlighted(code),
//       ),
//       h.pre(
//         [
//           a.id(pre_id),
//           a.style([
//             #("position", "absolute"),
//             #("top", "0"),
//             #("bottom", "0"),
//             #("left", "0"),
//             #("right", "0"),
//             #("margin", "0 !important"),
//             #("white-space", "pre-wrap"),
//             #("word-wrap", "break-word"),
//             #("overflow", "auto"),
//             #("color", "transparent"),
//           ]),
//         ],
//         underline(code, error_spans),
//       ),
//       // case parse_error {
//       //   Ok(_) -> none()
//       //   Error(reason) -> {
//       //     let from = case reason {
//       //       parser.UnexpectedToken(position: position, ..) -> position
//       //       parser.UnexpectEnd -> string.byte_size(code)
//       //     }
//       //     case pop_bytes(code, from, []) {
//       //       Ok(#(pre, post)) -> {
//       //         h.pre(
//       //           [
//       //             a.id(pre_id),
//       //             a.style([
//       //               #("position", "absolute"),
//       //               #("top", "0"),
//       //               #("bottom", "0"),
//       //               #("left", "0"),
//       //               #("right", "0"),
//       //               #("margin", "0 !important"),
//       //               #("white-space", "pre-wrap"),
//       //               #("word-wrap", "break-word"),
//       //               #("overflow", "auto"),
//       //               #("color", "transparent"),
//       //             ]),
//       //           ],
//       //           [
//       //             h.span([], [text(pre)]),
//       //             h.span(
//       //               [a.style([#("text-decoration", "red wavy underline;")])],
//       //               [text(post)],
//       //             ),
//       //           ],
//       //         )
//       //       }
//       //       Error(_) -> none()
//       //     }
//       //   }
//       // },
//       h.textarea(
//         [
//           a.style([
//             #("display", "block"),
//             // z-index can cause the highlight to be lot behind other containers. 
//             // make this position relative so stacked with absolute elements but do not move.
//             #("position", "relative"),
//             #("width", "100%"),
//             #("height", "100%"),
//             #("padding", "0 !important"),
//             #("margin", "0 !important"),
//             #("border", "0"),
//             #("color", "transparent"),
//             #("font-size", "1em"),
//             #("background-color", "transparent"),
//             #("outline", "2px solid transparent"),
//             #("outline-offset", "2px"),
//             #("caret-color", "black"),
//           ]),
//           a.attribute("spellcheck", "false"),
//           a.rows(text.line_count(code)),
//           e.on_input(on_update),
//           // stops navigation
//           e.on("keydown", fn(event) {
//             e.stop_propagation(event)
//             Error([])
//           }),
//           e.on("scroll", fn(event) {
//             let target =
//               event.target(dynamicx.unsafe_coerce(dynamic.from(event)))
//             window.request_animation_frame(fn(_) {
//               let target = dynamicx.unsafe_coerce(target)
//               let scroll_top = element.scroll_top(target)
//               let scroll_left = element.scroll_left(target)
//               let assert Ok(pre) = document.query_selector("#" <> pre_id)
//               element.set_scroll_top(pre, scroll_top)
//               element.set_scroll_left(pre, scroll_left)
//               Nil
//             })

//             Error([])
//           }),
//         ],
//         code,
//       ),
//     ],
//   )
// }

// import gleam/stringx

// fn highlighted(code) {
//   stringx.fold_graphemes(code, [], fn(acc, x) { [x, ..acc] })
//   code
//   |> lexer.lex()
//   |> list.map(pair.first)
//   |> highlight.highlight(highlight_token)
// }

// fn highlight_token(token) {
//   let #(classification, content) = token
//   let class = case classification {
//     highlight.Whitespace -> ""
//     highlight.Text -> ""
//     highlight.UpperText -> "text-blue-400"
//     highlight.Number -> "text-indigo-400"
//     highlight.String -> "text-green-500"
//     highlight.KeyWord -> "text-gray-700"
//     highlight.Effect -> "text-yellow-500"
//     highlight.Builtin -> "text-pink-400"
//     highlight.Reference -> "text-gray-400"
//     highlight.Punctuation -> ""
//     highlight.Unknown -> "text-red-500"
//   }
//   h.span([a.class(class)], [text(content)])
// }

// // fn underline(code, errors) {
// //   // let code = bit_array.from_string(code)
// //   let #(_, _, acc) =
// //     list.fold(errors, #(code, 0, []), fn(state, error) {
// //       let #(code, offset, acc) = state
// //       let #(start, end) = error
// //       let pre = start - offset
// //       let emp = end - start
// //       let offset = end
// //       let assert Ok(#(content, code)) = pop_bytes(code, pre, [])
// //       let acc = case content {
// //         "" -> acc
// //         content -> [h.span([], [text(content)]), ..acc]
// //       }
// //       let assert Ok(#(content, code)) = pop_bytes(code, emp, [])
// //       let acc = case content {
// //         "" -> acc
// //         content -> [
// //           h.span([a.style([#("text-decoration", "red wavy underline;")])], [
// //             text(content),
// //           ]),
// //           ..acc
// //         ]
// //       }
// //       #(code, offset, acc)
// //       // panic
// //       // case code {
// //       //   <<pre:bytes-size(pre), emp:bytes-size(emp), remaining:bytes>> -> {
// //       //     let assert Ok(pre) = bit_array.to_string(pre)
// //       //     let acc = case pre {
// //       //       "" -> acc
// //       //       content -> [h.span([], [text(content)]), ..acc]
// //       //     }
// //       //     let assert Ok(emp) = bit_array.to_string(emp)
// //       //     let acc = case emp {
// //       //       "" -> acc
// //       //       content -> [
// //       //         h.span([a.style([#("text-decoration", "red wavy underline;")])], [
// //       //           text(content),
// //       //         ]),
// //       //         ..acc
// //       //       ]
// //       //     }
// //       //     #(remaining, offset, acc)
// //       //   }
// //       //   _ -> panic
// //       // }
// //     })
// //   list.reverse(acc)
// // }

// fn underline(code, spans) {
//   // let code = bit_array.from_string(code)
//   let #(_, acc) =
//     list.fold(spans, #(0, []), fn(state, span) {
//       let #(offset, acc) = state
//       let #(start, end) = span
//       let pre =
//         h.span([], [text(stringx.byte_slice_range(code, offset, start))])
//       let range =
//         h.span([a.style([#("text-decoration", "red wavy underline;")])], [
//           text(stringx.byte_slice_range(code, start, end)),
//         ])
//       let offset = end
//       let acc = [range, pre, ..acc]
//       #(offset, acc)
//     })
//   list.reverse(acc)
// }

// fn pop_bytes(string, bytes, acc) {
//   case bytes {
//     0 -> Ok(#(string.concat(list.reverse(acc)), string))
//     x if x > 0 ->
//       case string.pop_grapheme(string) {
//         Ok(#(g, rest)) -> {
//           let bytes = bytes - string.byte_size(g)
//           let acc = [g, ..acc]
//           pop_bytes(rest, bytes, acc)
//         }
//         Error(Nil) -> Error(Nil)
//       }
//     _ -> {
//       io.debug("weird bytes")
//       Ok(#(string.concat(list.reverse(acc)), string))
//     }
//   }
// }

// pub fn separate_spans(spans) {
//   let spans =
//     list.sort(spans, fn(a, b) {
//       let #(start_a, _end) = a
//       let #(start_b, _end) = b
//       int.compare(start_a, start_b)
//     })
//   let #(_max, spans) =
//     list.map_fold(spans, 0, fn(max, value) {
//       let #(start, end) = value
//       let #(max, span) = case start {
//         _ if max <= start -> #(end, #(start, end))
//         _ if max <= end -> #(end, #(max, end))
//         _ -> #(max, #(max, max))
//       }
//       #(max, span)
//     })
//   spans
// }
