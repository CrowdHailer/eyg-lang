import eyg/interpreter/break
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import lustre/element/html as h
import morph/analysis
import website/components/example.{Example}
import website/components/output
import website/components/runner.{Runner}
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
      element.text("running effect" <> label),
    ]
    // if there is an unhandled effect error then
    False, _, Error(break.UnhandledEffect(label, _)), _ -> [
      element.text("will effect" <> label),
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
          list.map(warnings, fn(_) { element.text("watn") }),
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
