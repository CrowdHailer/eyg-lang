import eyg/analysis/type_/binding/debug
import eyg/interpreter/break
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/analysis
import website/components/example.{Example}
import website/components/output
import website/components/simple_debug
import website/components/snippet

pub fn render(state) {
  let Example(snippet:, runner:, ..) = state

  let break = case runner.return {
    Ok(value) -> Ok(value)
    Error(#(reason, _, _, _)) -> Error(reason)
  }

  // analysis is set on snippet after calculation
  let warnings = case snippet.analysis {
    Some(analysis) -> {
      analysis.type_errors(analysis)
    }
    None -> []
  }

  let slot = case runner.continue, runner.awaiting, break, warnings {
    // if running then show is running effect
    _, Some(_), Error(break.UnhandledEffect(label, _)), _ -> [
      snippet.footer_area(snippet.neo_blue_3, [
        element.text("Running effect " <> label),
      ]),
    ]
    // if there is an unhandled effect error then
    False, _, Error(break.UnhandledEffect(label, _)), [] -> [
      snippet.footer_area(snippet.neo_blue_3, [
        h.div([event.on_click(snippet.UserPressedCommandKey("Enter"))], [
          element.text("Will run effect " <> label <> ". "),
          h.button([], [element.text("Click to run.")]),
        ]),
      ]),
    ]
    // If there is no type errors but a runtime error it is because analysis is has not finished.
    False, _, Error(reason), [] -> {
      [element.text(simple_debug.reason_to_string(reason))]
    }
    // If not running show the value or type errors if not
    False, _, Ok(value), [] -> {
      [snippet.footer_area(snippet.neo_green_3, [output.render(value)])]
    }
    False, _, _, warnings -> {
      // What would be the correct error do we use the one with cache llokup built in
      [
        snippet.footer_area(
          snippet.neo_orange_4,
          list.map(warnings, fn(error) {
            let #(path, reason) = error
            h.div([event.on_click(snippet.UserClickedPath(path))], [
              reason_to_html(reason),
            ])
          }),
        ),
      ]
    }
    // Show single reason if we've run it.
    True, _, Error(reason), _ -> [
      element.text(simple_debug.reason_to_string(reason)),
    ]
    True, _, Ok(value), _ -> [
      snippet.footer_area(snippet.neo_green_3, [output.render(value)]),
    ]
  }
  snippet.render_embedded_with_top_menu(snippet, slot)
  |> element.map(example.SnippetMessage)
}

// could move to runner view
pub fn reason_to_html(r) {
  h.span([a.style([#("white-space", "nowrap")])], [
    element.text(debug.reason(r)),
  ])
}
// TODO note or error with context, be nice to jump to location of effect
// value
// runtime faile
// type errors (Only this one is a list)
// editor error 
// will perform
// 
// Error level action
// pub type TypeError {
//   ReleaseInvalid(package: String, release: Int)
//   ReleaseCheckDoesntMatch(
//     package: String,
//     release: Int,
//     published: String,
//     used: String,
//   )
//   ReleaseNotFetched(package: String, requested: Int, max: Int)
//   ReleaseFragmentNotFetched(package: String, release: Int, cid: String)
//   FragmentInvalid
//   ReferenceNotFetched
//   Todo
//   MissingVariable(String)
//   MissingBuiltin(String)
//   TypeMismatch(binding.Mono, binding.Mono)
//   MissingRow(String)
//   Recursive
//   SameTail(binding.Mono, binding.Mono)
// }

// Pass in if client is working
// pub fn type_errors(state) {
//   []
//   // todo as "probably move to mount"
//   // let Snippet(analysis:, cache:, ..) = state
//   // let errors = case analysis {
//   //   Some(analysis) -> analysis.type_errors(analysis)
//   //   None -> []
//   // }
//   // list.map(errors, fn(error) {
//   //   let #(meta, error) = error
//   //   let error = case error {
//   //     error.UndefinedRelease(p, r, cid) ->
//   //       case cache.fetch_named_cid(cache, p, r) {
//   //         Ok(c) if c == cid ->
//   //           case cache.fetch_fragment(cache, cid) {
//   //             Ok(cache.Fragment(value:, ..)) ->
//   //               case value {
//   //                 Ok(_) -> {
//   //                   io.debug(#("should have resolved ", p, r))
//   //                   ReleaseInvalid(p, r)
//   //                 }
//   //                 Error(#(reason, _, _, _)) -> ReleaseInvalid(p, r)
//   //                 // error info needs to be better 
//   //               }
//   //             Error(Nil) -> ReleaseFragmentNotFetched(p, r, c)
//   //           }
//   //         Ok(c) ->
//   //           ReleaseCheckDoesntMatch(
//   //             package: p,
//   //             release: r,
//   //             published: c,
//   //             used: cid,
//   //           )
//   //         // TODO client is still loading
//   //         Error(Nil) ->
//   //           case cache.max_release(cache, p) {
//   //             Error(Nil) -> ReleaseNotFetched(p, r, 0)
//   //             Ok(max) -> ReleaseNotFetched(p, r, max)
//   //           }
//   //       }
//   //     error.MissingReference(cid) ->
//   //       case cache.fetch_fragment(cache, cid) {
//   //         Ok(cache.Fragment(value:, ..)) ->
//   //           case value {
//   //             Ok(_) -> panic as "if the fragment was there it would be resolved"
//   //             Error(#(reason, _, _, _)) -> FragmentInvalid
//   //             // error info needs to be better 
//   //           }
//   //         Error(Nil) -> ReferenceNotFetched
//   //       }
//   //     error.Todo -> Todo
//   //     error.MissingVariable(var) -> MissingVariable(var)
//   //     error.MissingBuiltin(var) -> MissingBuiltin(var)
//   //     error.TypeMismatch(a, b) -> TypeMismatch(a, b)
//   //     error.MissingRow(l) -> MissingRow(l)
//   //     error.Recursive -> Recursive
//   //     error.SameTail(a, b) -> SameTail(a, b)
//   //   }
//   //   #(meta, error)
//   // })
// }
// fn render_structured_note_about_error(error) {
//   let #(path, reason) = error
//   // TODO color, don't border all errors
//   let reason = case reason {
//     ReleaseInvalid(p, r) ->
//       "The release @" <> p <> ":" <> int.to_string(r) <> " has errors."
//     ReleaseCheckDoesntMatch(package:, release:, ..) ->
//       "The release @"
//       <> package
//       <> ":"
//       <> int.to_string(release)
//       <> " does not use the published checksum."
//     ReleaseNotFetched(package, _, 0) ->
//       "The package '" <> package <> "' has not been published"
//     ReleaseNotFetched(package, r, n) ->
//       "The release "
//       <> int.to_string(r)
//       <> " for '"
//       <> package
//       <> "' is not available. Latest publish is "
//       <> int.to_string(n)
//     ReleaseFragmentNotFetched(package:, release:, ..) ->
//       "The release @"
//       <> package
//       <> ":"
//       <> int.to_string(release)
//       <> " is still loading."
//     FragmentInvalid -> "FragmentInvalid"
//     ReferenceNotFetched -> "ReferenceNotFetched"
//     Todo -> "The program is incomplete."
//     MissingVariable(var) ->
//       "The variable '" <> var <> "' is not available here."
//     MissingBuiltin(identifier) ->
//       "The built-in function '!" <> identifier <> "' is not implemented."
//     TypeMismatch(_t, _t) -> "TypeMismatch"
//     MissingRow(_) -> "MissingRow"
//     Recursive -> "Recursive"
//     SameTail(_t, _t) -> "SameTail"
//   }
//   h.div([event.on_click(UserClickedPath(path))], [element.text(reason)])
//   // radio shows just one of the errors open at a time
//   // h.details([], [
//   //   h.summary([], [element.text(reason)]),
//   //   h.div([], [element.text("MOOOOARE")]),
//   // ])
// }

// fn render_run(run, evaluated) {
//   case run {
//     NotRunning ->
//       case evaluated {
//         Ok(#(value, _scope)) ->
//           footer_area(neo_green_3, [
//             case value {
//               Some(value) -> output.render(value)
//               None -> element.none()
//             },
//           ])
//         Error(#(break.UnhandledEffect(label, _), _, _, _)) ->
//           footer_area(neo_blue_3, [
//             h.span([event.on_click(UserClickRunEffects)], [
//               element.text("Will run "),
//               element.text(label),
//               element.text(" effect. click to continue."),
//             ]),
//           ])
//         Error(#(reason, _, _, _)) ->
//           footer_area(neo_orange_4, [
//             element.text(simple_debug.reason_to_string(reason)),
//           ])
//       }
//     Running(Ok(#(value, _scope)), _effects) ->
//       // (value, _) ->
//       footer_area(neo_green_3, [
//         case value {
//           Some(value) -> output.render(value)
//           None -> element.none()
//         },
//       ])
//     Running(Error(#(break.UnhandledEffect(_label, _), _, _, _)), _effects) ->
//       footer_area(neo_green_3, [element.text("running")])

//     // run.Handling(label, _meta, _env, _stack, _blocking) ->
//     Running(Error(#(reason, _, _, _)), _effects) ->
//       footer_area(neo_orange_4, [
//         element.text(simple_debug.reason_to_string(reason)),
//       ])
//   }
// }
