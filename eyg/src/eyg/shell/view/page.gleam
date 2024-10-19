import eyg/shell/state
import eyg/website/components/output
import eyg/website/components/snippet
import gleam/dynamic
import gleam/dynamicx
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import morph/lustre/render
import morph/pallet

pub fn render(state) {
  let state.Shell(
    situation: _,
    cache: _cache,
    display_help: display_help,
    previous: previous,
    scope: _scope,
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
              render_previous(dynamicx.unsafe_coerce(dynamic.from(previous))),
            ),
            snippet.render_sticky(snippet)
              |> element.map(state.SnippetMessage),
          ],
        ),
        case display_help {
          True ->
            h.div([a.class("bg-indigo-100 p-4 rounded-2xl")], [
              pallet.key_references(),
            ])

          False -> element.none()
        },
      ],
    ),
  ])
}

fn render_previous(previous) {
  list.map(list.reverse(previous), fn(p) {
    let #(value, prog) = p
    h.div([a.class("w-full max-w-4xl mt-2 py-1 bg-white shadow-xl rounded")], [
      h.div(
        [a.class("px-3 whitespace-nowrap overflow-auto")],
        render.statements(prog),
      ),
      case value {
        Some(value) ->
          h.div([a.class("mx-3 pt-1 border-t max-h-60 overflow-auto")], [
            output.render(value),
          ])
        None -> element.none()
      },
    ])
  })
}
