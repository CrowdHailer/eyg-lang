import drafting/view/page as drafting
import eyg/shell/state
import eyg/website/components/snippet
import gleam/dynamic
import gleam/dynamicx
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import spotless/view/page as spotpage

pub fn render(state) {
  let state.Shell(
    situation: _,
    cache: cache,
    display_help: display_help,
    previous: previous,
    scope: scope,
    source: snippet,
  ) = state

  h.div([a.class("flex flex-col h-screen")], [
    h.div([a.class("w-full fixed py-2 px-6 text-xl text-gray-500")], [
      h.a([a.href("/"), a.class("font-bold")], [element.text("EYG")]),
      h.span([a.class("")], [element.text(" - Editor")]),
    ]),
    h.div(
      [
        a.class("hstack flex-1 h-screen overflow-hidden"),
        // a.style([#("height", "100%")])
      ],
      [
        h.div(
          [
            a.class(
              "flex-grow flex flex-col justify-center w-full max-w-3xl font-mono px-6 max-h-full overflow-scroll",
            ),
          ],
          [
            element.fragment(
              spotpage.render_previous(
                dynamicx.unsafe_coerce(dynamic.from(previous)),
              ),
            ),
            snippet.render_sticky(snippet)
              |> element.map(state.SnippetMessage),
          ],
        ),
        case display_help {
          True ->
            h.div([a.class("bg-indigo-100 p-4 rounded-2xl")], [
              drafting.key_references(),
            ])

          False -> element.none()
        },
      ],
    ),
  ])
}
