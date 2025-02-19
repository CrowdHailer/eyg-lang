// import eyg/analysis/inference/levels_j/contextual as j
// import eyg/analysis/type_/isomorphic
// import eyg/document/section
// import eyg/package
// import eyg/interpreter/break
// import eyg/interpreter/cast
// import eyg/interpreter/expression as r
// import eyg/interpreter/state.{type Env, type Stack} as istate
// import eyg/interpreter/value as v
// import website/sync/browser
// import website/sync/fragment
// import website/sync/packages
// import website/sync/sync
// import eygir/encode
// import gleam/dict
// import gleam/http/request.{type Request}
// import gleam/io
// import gleam/javascript/promise
// import gleam/list
// import gleam/listx
// import gleam/option.{type Option, None, Some}
// import gleam/result
// import gleam/uri
// import harness/fetch
// import harness/http
// import website/harness/browser/geolocation
// import website/harness/browser/now
// import website/harness/browser/visit
// import intro/content
// import lustre/effect
// import midas/browser as m_browser
// import morph/analysis
// import morph/buffer
// import morph/editable
// import morph/picker
// import morph/projection

// // import plinth/browser/geolocation
// import plinth/browser/document
// import plinth/browser/element
// import plinth/browser/window
// import plinth/javascript/global
// import snag.{type Snag}

// pub fn update_focus() {
//   window.request_animation_frame(fn(_) {
//     case document.query_selector("#focus-input") {
//       Ok(el) -> {
//         element.focus(el)
//       }
//       _ -> {
//         let assert Ok(el) = document.query_selector("#code")
//         element.focus(el)
//       }
//     }
//   })
// }

// // circular dependency on content potential if init calls content and content needs sections
// // init should take some value

// pub type Effect {
//   Awaited(Value)
//   Log(String)
//   Asked(question: String, answer: String)
//   Fetched(request: Request(BitArray))
//   Waited(Int)
//   Geolocation(reply: geolocation.Reply)
// }

// pub type For {
//   Loading(reference: String)
//   Awaiting(promise.Promise(Value))
//   Geo
//   Timer(duration: Int)
//   TextInput(question: String, response: String)
// }

// pub type Handle(a) {
//   Abort(istate.Debug(a))
//   Suspended(for: For, Env(a), Stack(a))
//   Done(Value)
// }

// pub type Runner(a) {
//   Runner(handle: Handle(a), effects: List(Effect))
// }

// pub type Focus {
//   Focus(
//     scope: package.Scope,
//     comments: List(String),
//     buffer: #(projection.Projection, buffer.Mode),
//     after: List(package.Section),
//   )
// }

// // work state
// pub type Working {
//   Complete(public: List(String), hash: String)
//   Working(Focus)
// }

// pub type Guide {
//   Guide(before: List(package.Section), working: Working)
// }

// type Path =
//   List(Int)

// type Value =
//   v.Value(Path, #(List(#(istate.Kontinue(Path), Path)), Env(Path)))

// fn load_reference(state, ref, result) {
//   todo as "should this be explicit"
//   // let State(references: store, ..) = state
//   // let store = sync.fetched_reference(store, ref, result)
//   // State(..state, references: store)
// }

// fn focus_at(document, index, cache) {
//   let #(cache, reversed) = loose_focus(document, cache)
//   let result = case listx.split_around(list.reverse(reversed), index) {
//     Ok(#(before, section, after)) -> {
//       let scope = package.scope_at(before)

//       let package.Section(content, _processed) = section
//       let section.Section(comments, snippet) = content

//       // TODO buffer from assigns
//       let assert Ok(proj) =
//         projection.focus_in_block(snippet, editable.Vacant, [0], [])
//       let mode = buffer.Command(None)
//       let buffer = #(proj, mode)

//       let focus = Focus(scope, comments, buffer, after)

//       let document = Guide(before, Working(focus))
//       Ok(document)
//     }
//     Error(Nil) -> Error(Nil)
//   }
//   #(cache, result)
// }

// fn loose_focus(document, cache: sync.Sync) {
//   let Guide(before, focus) = document
//   // let before = list.reverse(before)
//   let #(cache, before) = case focus {
//     Complete(_, _) -> #(cache, before)
//     Working(Focus(scope, comments, buffer, after)) -> {
//       let #(projection, _) = buffer
//       let assigns = case projection.rebuild(projection) {
//         editable.Block(assigns, _, _) -> assigns
//         _ -> todo as "bad block"
//       }
//       let after = list.map(after, fn(s: package.Section) { s.content })
//       let remaining = [section.Section(comments, assigns), ..after]
//       package.do_eval_sections(remaining, before, scope, cache)
//     }
//   }

//   #(cache, before)
// }

// pub type State {
//   State(
//     package: Option(#(String, String)),
//     document: Guide,
//     cache: sync.Sync,
//     running: Option(#(String, Runner(Path))),
//   )
// }

// // everything reactive means that even if cached locally we should go through the same process
// // or switch to an enum on a statue for remotedata unknown
// fn get_package() {
//   use uri <- result.try(uri.parse(window.location()))
//   case uri.path_segments(uri.path) {
//     ["packages", group, name] -> Ok(#(group, name))
//     _ -> Error(Nil)
//   }
// }

// fn sync(state: State, dispatch) {
//   let assert Ok(origin) = uri.parse(window.location())
//   case state.package {
//     // ignote intro
//     //  best not to special case guide i.e. dogfood text dogfood
//     Some(#("eyg", "intro")) -> {
//       let sections = package.sections_from_content(content.intro_content())
//       dispatch(LoadedGuide(#("eyg", "intro"), Ok(sections)))
//     }
//     Some(#("eyg", "http")) -> {
//       let sections = package.sections_from_content(content.http_content())
//       dispatch(LoadedGuide(#("eyg", "http"), Ok(sections)))
//     }

//     // Some(#("eyg", "json")) -> {
//     //   let sections = package.sections_from_content(content.json_content())
//     //   let assigns =
//     //     list.flat_map(sections, fn(section) {
//     //       list.fold_right(
//     //         section.comments,
//     //         section.snippet,
//     //         fn(snippet, comment) {
//     //           [#(editable.Bind("_"), editable.String(comment)), ..snippet]
//     //         },
//     //       )
//     //     })
//     //   io.println(
//     //     editable.to_expression(editable.Block(
//     //       assigns,
//     //       editable.Vacant,
//     //       True,
//     //     ))
//     //     |> encode.to_json,
//     //   )
//     //   dispatch(LoadedGuide(#("eyg", "json"), Ok(sections)))
//     // }
//     Some(package) -> {
//       let #(group, name) = package
//       let task = packages.fetch_remote(origin, group, name)

//       promise.map(m_browser.run(task), fn(result) {
//         dispatch(LoadedPackage(package, result))
//       })
//       Nil
//     }
//     None -> {
//       Nil
//     }
//   }
// }

// fn sync_cache(state) {
//   let State(cache: cache, ..) = state
//   let #(cache, tasks) = sync.fetch_all_missing(cache)
//   let state = State(..state, cache: cache)
//   #(state, effect.from(browser.do_sync(tasks, Synced)))
// }

// fn build_guide(cache: sync.Sync, before) {
//   let #(cache, before, public, ref) = package.build_guide(cache, before)
//   let guide = Guide(before, Complete(public, ref))
//   #(cache, guide)
// }

// pub fn init(_) {
//   let cache = sync.init(browser.get_origin())

//   let package = get_package() |> option.from_result
//   let #(cache, document) = build_guide(cache, [])
//   let state = State(package, document, cache, None)
//   #(state, effect.from(sync(state, _)))
// }

// pub type ExecutorMessage {
//   Update(For)
//   Resume(Effect)
// }

// // The runner is just left up until dismessed so a value is always returned
// pub fn update_executor(run, message) {
//   case message {
//     Update(for) -> {
//       let assert Runner(Suspended(_, env, k), effects) = run
//       Runner(Suspended(for, env, k), effects)
//     }
//     Resume(reply) -> {
//       let assert Runner(Suspended(_, env, k), effects) = run

//       let value = reply_value(reply)
//       let result = r.loop(istate.step(istate.V(value), env, k))
//       let effects = [reply, ..effects]
//       do_handle_next(result, effects)
//     }
//   }
// }

// pub type Message {
//   Synced(sync.Message)
//   EditCode(index: Int, content: String)
//   KeyDown(String)
//   UpdateSuspend(For)
//   Buffer(buffer.Message)
//   UpdatePicker(picker.Message)
//   Run(String)
//   Unsuspend(Effect)
//   // execute after assumes boolean information probably should be list of args and/or reference to possible effects
//   LoadedReference(reference: String, value: Result(expression.Expression, Snag))
//   LoadedPackage(
//     package: #(String, String),
//     result: Result(expression.Expression, Snag),
//   )
//   LoadedGuide(
//     package: #(String, String),
//     result: Result(List(section.Section), Snag),
//   )
//   FocusOnSnippet(index: Int)
//   Blur
//   CloseRunner
// }

// pub fn block_drop_meta(assigns, then) {
//   let assigns =
//     list.map(assigns, fn(assign) {
//       let #(label, value, _meta) = assign
//       #(label, annotated.drop_annotation(value))
//     })
//   let then = option.map(then, annotated.drop_annotation)
//   #(assigns, then)
// }

// pub fn context_from_scope(scope, cache: sync.Sync) {
//   let types = sync.types(cache)
//   let scope =
//     list.filter_map(scope, fn(assign) {
//       let #(label, ref) = assign

//       case dict.get(types, ref) {
//         Ok(poly) -> Ok(#(label, poly))
//         Error(Nil) -> Error(Nil)
//       }
//     })
//   analysis.Context(
//     // bindings are empty as long as everything is properly poly
//     bindings: dict.new(),
//     scope: scope,
//     references: types,
//     builtins: j.builtins(),
//   )
// }

// // TODO this needs to not go to previous variables
// pub fn analyse(projection, scope, cache: sync.Sync) {
//   let context = context_from_scope(scope, cache)
//   // TODO real effect
//   analysis.analyse(projection, context, isomorphic.Empty)
// }

// pub fn analysis_env_after(before, cache: sync.Sync) {
//   // TODO write a test case that checks previous types are fully qualified
//   let types = sync.types(cache)
//   let scope =
//     list.map(package.scope_at(before), fn(assign) {
//       let #(label, ref) = assign
//       let poly = case dict.get(types, ref) {
//         Ok(poly) -> poly
//         Error(Nil) -> j.q(0)
//       }

//       #(label, poly)
//     })
//   analysis.Context(
//     // bindings are empty as long as everything is properly poly
//     bindings: dict.new(),
//     scope: scope,
//     references: types,
//     builtins: j.builtins(),
//   )
// }

// // This assumes command mode
// pub fn buffer_update(buffer, message, context) {
//   let #(proj, mode) = buffer
//   case message {
//     // buffer.Submit ->
//     //   case buffer.handle_submit(mode) {
//     //     Ok(buffer) -> buffer
//     //     Error(Nil) -> #(proj, mode)
//     //   }
//     // buffer.UpdateInput(new) -> {
//     //   let mode = buffer.handle_input(mode, new)
//     //   #(proj, mode)
//     // }
//     // buffer.KeyDown(key) -> {
//     //   buffer.handle_keydown(key, context, proj, mode, [])
//     // }
//     _ -> todo as "i dont think this should happen"
//   }
// }

// pub fn update(state, message) {
//   let State(cache: cache, ..) = state
//   case message {
//     Synced(message) -> {
//       let cache = sync.task_finish(cache, message)
//       let #(cache, tasks) = sync.fetch_all_missing(cache)
//       let state = State(..state, cache: cache)
//       #(state, effect.from(browser.do_sync(tasks, Synced)))
//     }
//     EditCode(index, new) -> {
//       todo as "edit code"
//       // let State(document: document, ..) = state
//       // let #(references, document) =
//       //   snippet.update_at(document, index, new, references)
//       // let missing = snippet.missing_references(document)
//       // let state = State(..state, document: document, references: references)
//       // #(state, effect.from(load_new_references(missing, _)))
//     }
//     KeyDown(key) -> {
//       let Guide(before, focus) = state.document
//       case focus {
//         Working(Focus(buffer: #(projection, buffer.Command(_)), ..) as focus) -> {
//           let env = analysis_env_after(before, cache)
//           let buffer = buffer.handle_command(key, projection, env, [])

//           let focus = Working(Focus(..focus, buffer: buffer))
//           let document = Guide(before, focus)
//           let state = State(..state, document: document)
//           update_focus()
//           #(state, effect.none())
//         }
//         _ -> {
//           io.debug("unexpected keydowb")
//           #(state, effect.none())
//         }
//       }
//     }
//     Buffer(m) -> {
//       let Guide(before, focus) = state.document
//       case focus {
//         Working(Focus(buffer: buffer, ..) as focus) -> {
//           let buffer =
//             buffer_update(buffer, m, analysis_env_after(before, cache))
//           let focus = Working(Focus(..focus, buffer: buffer))

//           let document = Guide(before, focus)
//           let state = State(..state, document: document)
//           update_focus()
//           #(state, effect.none())
//         }
//         Complete(_, _) -> #(state, effect.none())
//       }
//     }
//     UpdatePicker(m) -> {
//       let Guide(before, focus) = state.document
//       case focus {
//         Working(
//           Focus(
//             buffer: #(proj, buffer.Pick(picker, rebuild)),
//             ..,
//           ) as focus,
//         ) -> {
//           let buffer = case m {
//             picker.Updated(picker) -> {
//               let mode = buffer.Pick(picker, rebuild)
//               #(proj, mode)
//             }
//             picker.Decided(value) -> {
//               let mode = buffer.Command(None)
//               #(rebuild(value), mode)
//             }
//             picker.Dismissed -> {
//               let mode = buffer.Command(None)
//               #(proj, mode)
//             }
//           }
//           let focus = Working(Focus(..focus, buffer: buffer))
//           let document = Guide(before, focus)
//           let state = State(..state, document: document)
//           #(state, effect.none())
//         }

//         _ -> #(state, effect.none())
//       }
//     }
//     UpdateSuspend(for) -> {
//       let State(running: running, ..) = state
//       let assert Some(#(ref, run)) = running
//       let assert Runner(Suspended(_, env, k), effects) = run

//       let state =
//         State(
//           ..state,
//           running: Some(#(ref, Runner(Suspended(for, env, k), effects))),
//         )
//       #(state, effect.none())
//     }
//     FocusOnSnippet(index) -> {
//       let #(cache, result) = focus_at(state.document, index, cache)
//       let state = case result {
//         Ok(document) -> State(..state, document: document, cache: cache)
//         Error(Nil) -> State(..state, cache: cache)
//       }
//       #(state, effect.none())
//     }
//     Blur -> {
//       let #(cache, before) = loose_focus(state.document, cache)
//       let #(cache, document) = build_guide(cache, before)
//       let state = State(..state, document: document, cache: cache)
//       sync_cache(state)
//     }
//     Run(reference) -> {
//       let values = sync.values(cache)
//       let assert Ok(func) = dict.get(values, reference)
//       let #(run, effect) =
//         handle_next(
//           r.call(func, [#(v.unit(), [])], fragment.empty_env(values), dict.new()),
//           [],
//         )
//       let state = State(..state, running: Some(#(reference, run)))
//       #(state, effect)
//     }

//     Unsuspend(effect) -> {
//       let State(running: running, ..) = state
//       let assert Some(#(ref, run)) = running
//       let assert Runner(Suspended(_, env, k), effects) = run

//       let value = reply_value(effect)
//       let result = r.loop(istate.step(istate.V(value), env, k))
//       let effects = [effect, ..effects]
//       let #(run, effect) = handle_next(result, effects)

//       let state = State(..state, running: Some(#(ref, run)))
//       #(state, effect)
//     }

//     LoadedReference(reference, result) -> {
//       let state = load_reference(state, reference, result)
//       #(state, effect.none())
//     }
//     LoadedPackage(package, result) -> {
//       io.debug("loading package")
//       let assert Ok(source) = result
//       let #(cache, before, public, ref) =
//         package.load_guide_from_expression(source, cache)
//       let guide = Guide(before, Complete(public, ref))

//       let state = State(..state, document: guide, cache: cache)
//       #(state, effect.none())
//     }
//     LoadedGuide(package, result) -> {
//       io.debug("loading package")
//       let assert Ok(sections) = result
//       let #(cache, before, public, ref) = package.load_guide(sections, cache)
//       let guide = Guide(before, Complete(public, ref))

//       let state = State(..state, document: guide, cache: cache)
//       #(state, effect.none())
//     }
//     CloseRunner -> {
//       let state = State(..state, running: None)
//       #(state, effect.none())
//     }
//   }
// }

// fn reply_value(effect) -> Value {
//   case effect {
//     Geolocation(result) -> geolocation.result_to_eyg(result)
//     Asked(_question, answer) -> v.String(answer)
//     Waited(_duration) -> v.unit
//     Awaited(value) -> value
//     Log(_) -> panic as "log can be dealt with synchronously"
//     Fetched(_) -> panic as "fetch returns a promise"
//   }
// }

// pub fn do_handle_next(result: Result(Value, #(_, _, Env(Path), _)), effects) {
//   case result {
//     Error(#(reason, meta, env, k)) ->
//       case reason {
//         break.UnhandledEffect(label, lift) ->
//           case label {
//             "Ask" ->
//               case cast.as_string(lift) {
//                 Ok(question) ->
//                   Runner(Suspended(TextInput(question, ""), env, k), effects)
//                 Error(reason) -> Runner(Abort(#(reason, meta, env, k)), effects)
//               }
//             "Log" ->
//               case cast.as_string(lift) {
//                 Ok(message) -> {
//                   let effects = [Log(message), ..effects]
//                   r.loop(istate.step(istate.V(v.unit()), env, k))
//                   |> do_handle_next(effects)
//                 }
//                 Error(reason) -> Runner(Abort(#(reason, meta, env, k)), effects)
//               }
//             "Wait" ->
//               case cast.as_integer(lift) {
//                 Ok(duration) ->
//                   Runner(Suspended(Timer(duration), env, k), effects)
//                 // r.loop(istate.step(
//                 //   istate.V(v.Promise(
//                 //     promise.wait(duration) |> promise.map(fn(_) { v.unit() }),
//                 //   )),
//                 //   env,
//                 //   k,
//                 // ))
//                 // |> do_handle_next(effects)
//                 Error(reason) -> Runner(Abort(#(reason, meta, env, k)), effects)
//               }

//             "Geo" -> Runner(Suspended(Geo, env, k), effects)
//             "Fetch" ->
//               case http.request_to_gleam(lift) {
//                 Ok(request) -> {
//                   let task = fetch.do(request)
//                   let value = fetch.task_to_eyg(task)
//                   let effects = [Fetched(request), ..effects]

//                   r.loop(istate.step(istate.V(value), env, k))
//                   |> do_handle_next(effects)
//                 }
//                 Error(reason) -> Runner(Abort(#(reason, meta, env, k)), effects)
//               }
//             "Now" ->
//               case now.impl(lift) {
//                 Ok(reply) -> {
//                   let effects = [Log("Now: " <> old_value.debug(reply)), ..effects]
//                   r.loop(istate.step(istate.V(reply), env, k))
//                   |> do_handle_next(effects)
//                 }
//                 Error(reason) -> Runner(Abort(#(reason, meta, env, k)), effects)
//               }
//             "Open" ->
//               case visit.impl(lift) {
//                 Ok(reply) -> {
//                   let effects = [Log("Open: " <> old_value.debug(reply)), ..effects]
//                   r.loop(istate.step(istate.V(reply), env, k))
//                   |> do_handle_next(effects)
//                 }
//                 Error(reason) -> Runner(Abort(#(reason, meta, env, k)), effects)
//               }
//             "Await" ->
//               case cast.as_promise(lift) {
//                 Ok(task) -> Runner(Suspended(Awaiting(task), env, k), effects)
//                 Error(reason) -> Runner(Abort(#(reason, meta, env, k)), effects)
//               }

//             _other -> Runner(Abort(#(reason, meta, env, k)), effects)
//           }
//         reason -> Runner(Abort(#(reason, meta, env, k)), effects)
//       }
//     Ok(value) -> Runner(Done(value), effects)
//   }
// }

// pub fn handle_next(result, effects) {
//   let Runner(handle, _effects) as run = do_handle_next(result, effects)
//   let effect = case handle {
//     Suspended(for, _env, _k) ->
//       case for {
//         Timer(duration) ->
//           effect.from(fn(d) {
//             global.set_timeout(duration, fn() {
//               d(Unsuspend(Waited(duration)))
//               Nil
//             })
//             Nil
//           })

//         Geo -> {
//           effect.from(fn(d) {
//             geolocation.do()
//             |> promise.map(fn(result) { d(Unsuspend(Geolocation(result))) })
//             Nil
//           })
//         }
//         Awaiting(task) -> {
//           effect.from(fn(d) {
//             promise.map(task, fn(value) { d(Unsuspend(Awaited(value))) })
//             Nil
//           })
//         }
//         _ -> effect.none()
//       }

//     _ -> effect.none()
//   }
//   #(run, effect)
// }
