import eyg/analysis/inference/levels_j/contextual as j
import eyg/shell/examples
import eyg/shell/state
import eyg/sync/sync
import eyg/website/components/snippet
import gleam/dict
import gleam/dynamic
import gleam/dynamicx
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import lustre/element/html as h
import morph/analysis
import spotless/view/page as spotpage

pub fn render(state) {
  let state.Shell(
    situation: _,
    cache: cache,
    previous: previous,
    scope: scope,
    source: snippet,
  ) = state

  h.div([], [
    element.fragment(
      spotpage.render_previous(dynamicx.unsafe_coerce(dynamic.from(previous))),
    ),
    snippet.render(snippet)
      |> element.map(state.SnippetMessage),
    element.text(int.to_string(list.length(previous))),
    // element.text(string.inspect(snippet.run(snippet))),
  ])
}
