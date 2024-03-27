import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/stringx
import lustre/attribute as a
import lustre/element/html as h
import lustre/element.{text}
import lustre/event
import drafting/session as d
import drafting/view/page
import morph/lustre/render
import eyg/runtime/value as v
import spotless/state

pub fn render(app) {
  let state.State(previous, env, current, error) = app
  // containter for relative positioning
  h.div(
    [a.class("vstack bg-gray-100 font-mono")],
    list.map(list.reverse(previous), fn(p) {
        let #(value, prog) = p
        h.div([a.class("w-full max-w-3xl mt-2 bg-white shadow-xl rounded")], [
          h.div([a.class("py-1 px-3")], render.top(prog)),
          h.div([a.class("py-1 px-3")], [text(v.debug(value))]),
        ])
      })
      |> list.append([
        // h.div([TODO can have a help at the bottom], [text("spotless")]),
        h.div(
          [
            a.class(
              "w-full max-w-3xl mt-2 bg-white shadow-xl rounded overflow-hidden",
            ),
          ],
          [
            h.div([a.class("py-1 px-3")], [
              page.surface(current.projection)
              |> element.map(state.Drafting),
            ]),
            ..case current.mode {
              d.Navigate ->
                case error {
                  state.Failed(reason) -> [
                    h.div([a.class("w-full orange-gradient text-white px-3")], [
                      text(reason),
                    ]),
                  ]
                  state.Running -> [
                    h.div([a.class("w-full green-gradient px-3")], [
                      text("running ..."),
                    ]),
                  ]
                  _ -> [
                    h.div([a.class("w-full orange-gradient text-white")], [
                      h.div([], []),
                      ..list.map(
                        state.type_errors(current.projection, env),
                        fn(e) {
                          let #(path, reason) = e
                          let path = list.reverse(path)
                          h.div([a.class("px-3")], [
                            h.a([event.on_click(state.JumpTo(path))], [
                              text(path_to_string(path)),
                            ]),
                            text(" "),
                            text(reason),
                          ])
                        },
                      )
                    ]),
                  ]
                }
              d.SelectAction(search, suggestions, index) ->
                overlay([
                  page.pallet(search, suggestions, index)
                  |> element.map(state.Drafting),
                ])
              d.EditString(value, _rebuild) ->
                overlay([
                  page.string_input(value)
                  |> element.map(state.Drafting),
                ])
              d.SelectBuiltin(value, suggestions, index, _) ->
                overlay([
                  page.select_builtin(value, suggestions, index)
                  |> element.map(state.Drafting),
                ])
              d.SelectVariable(value, index, _) ->
                overlay([
                  {
                    let vars = state.vars_from_env(env)
                    let vars = list.filter(vars, string.contains(_, value))
                    let index = index % list.length(vars)
                    page.select_builtin(value, vars, index)
                  }
                  |> element.map(state.Drafting),
                ])
            }
          ],
        ),
      ]),
  )
}

fn overlay(content) {
  [
    h.div(
      [
        a.class(
          "bg-black text-white border-black mx-auto max-w-2xl border w-full rounded",
        ),
      ],
      content,
    ),
  ]
}

fn path_to_string(path) {
  list.map(path, int.to_string)
  |> string.join(",")
  |> stringx.wrap("[", "]")
}
