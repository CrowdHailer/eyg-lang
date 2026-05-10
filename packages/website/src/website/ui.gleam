import eyg/analysis/inference/levels_j/contextual as infer
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import gleam/dynamic/decode
import gleam/dynamicx
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/buffer
import morph/input
import morph/lustre/frame
import morph/lustre/highlight
import morph/lustre/render
import morph/picker
import morph/projection as p
import plinth/browser/element as pelement
import plinth/browser/event as pevent
import website/manipulation
import website/run

pub const code_area_styles = [
  #("outline", "2px solid transparent"),
  #("outline-offset", "2px"),
  #("padding", ".5rem"),
  #("white-space", "nowrap"),
  #("overflow", "auto"),
  #("margin-top", "auto"),
  #("margin-bottom", "auto"),
  #("height", "100%"),
]

pub const embed_area_styles = [
  #("box-shadow", "6px 6px black"),
  #("border-style", "solid"),
  #(
    "font-family",
    "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace",
  ),
  #("background-color", "rgb(255, 255, 255)"),
  #("border-color", "rgb(0, 0, 0)"),
  #("border-width", "1px"),
  #("flex-direction", "column"),
  #("display", "flex"),
  #("margin-bottom", "1.5rem"),
  #("margin-top", ".5rem"),
]

pub type ExampleState {
  Editing(manipulation.UserInput)
  Errors(List(String))
  Pending
  Running(run.Run(state.Value(List(Int))))
}

// This is a bit back to front it shouldn't take the mode and ID instead we need a view model
pub fn example(
  buffer: buffer.Buffer,
  state: ExampleState,
  user_clicked_code: fn(List(Int)) -> m,
  picker_message: fn(picker.Message) -> m,
  input_message: fn(input.Message) -> m,
) -> element.Element(m) {
  h.div([a.styles(embed_area_styles)], [
    code(buffer.projection, buffer.analysis, user_clicked_code),
    case state {
      Editing(manipulation.PickSingle(picker, _)) ->
        picker.render(picker) |> element.map(picker_message)
      Editing(manipulation.PickCid(picker, _)) ->
        picker.render(picker) |> element.map(picker_message)
      Editing(manipulation.EnterText(value, _)) ->
        input.render_text(value) |> element.map(input_message)
      Editing(manipulation.EnterInteger(value, _)) ->
        input.render_number(value) |> element.map(input_message)
      Editing(manipulation.PickRelease(picker, _)) ->
        picker.render(picker) |> element.map(picker_message)
      Errors(errors) ->
        h.div(
          [
            a.class("border-2 border-orange-3 px-2"),
            a.styles([#("overflow-x", "auto")]),
          ],
          list.map(errors, fn(reason) {
            // let #(_path, reason) = error
            h.div(
              [
                // event.on_click(state.SnippetMessage(
              //   state.hot_reload_key,
              //   snippet.UserClickedPath(path),
              // )),
              ],
              [element.text(reason)],
            )
          }),
        )

      Pending ->
        h.div(
          [
            a.class("border-2 border-blue-3 px-2"),
            a.styles([#("overflow-x", "auto")]),
          ],
          [
            h.text("Enter to run."),
          ],
        )
      Running(run.Concluded(value)) ->
        h.pre(
          [
            a.class("border-2 border-green-3 px-2"),
            a.styles([#("overflow-x", "auto")]),
          ],
          [
            h.text(simple_debug.inspect(value)),
          ],
        )
      Running(run.Exception(reason)) ->
        h.div(
          [
            a.class("border-2 border-orange-3 px-2"),
            a.styles([#("overflow-x", "auto")]),
          ],
          [
            h.text(simple_debug.describe(reason)),
          ],
        )
      Running(run.Aborted(reason)) ->
        h.div(
          [
            a.class("border-2 border-orange-3 px-2"),
            a.styles([#("overflow-x", "auto")]),
          ],
          [
            h.text(reason),
          ],
        )
      Running(run.Handling(..)) ->
        h.div(
          [
            a.class("border-2 border-blue-3 px-2"),
            a.styles([#("overflow-x", "auto")]),
          ],
          [
            h.text("running"),
          ],
        )
      Running(run.Pending(..)) ->
        h.div(
          [
            a.class("border-2 border-blue-3 px-2"),
            a.styles([#("overflow-x", "auto")]),
          ],
          [
            h.text("running"),
          ],
        )
    },
  ])
}

/// render a code projection with errors and focus
pub fn code(projection, analysis, user_clicked_code) {
  h.pre(
    [
      a.class("language-eyg"),
      a.styles(code_area_styles),
      event.on("click", code_path_click_decoder(user_clicked_code)),
    ],
    [
      render_projection(projection, infer.all_errors(analysis)),
    ],
  )
}

pub fn render_projection(
  proj: #(p.Focus, List(p.Break)),
  errors: List(#(List(Int), a)),
) -> element.Element(b) {
  let #(focus, zoom) = proj
  case focus, zoom {
    p.Exp(e), [] ->
      frame.Statements(render.statements(e, errors))
      |> highlight.frame(highlight.focus())
      |> frame.to_fat_line
    _, _ -> {
      // This is NOT reversed because zoom works from inside out
      let frame = render.projection_frame(proj, render.Statements, errors)
      render.push_render(frame, zoom, render.Statements, errors)
      |> frame.to_fat_line
    }
  }
}

pub fn code_path_click_decoder(
  user_clicked_code: fn(List(Int)) -> a,
) -> decode.Decoder(a) {
  decode.new_primitive_decoder("click", fn(event) {
    let assert Ok(e) = pevent.cast_event(event)
    let target = pevent.target(e)
    let rev =
      target
      |> dynamicx.unsafe_coerce
      |> pelement.dataset_get("rev")
    case rev {
      Ok(rev) -> {
        let assert Ok(rev) = case rev {
          "" -> Ok([])
          _ ->
            string.split(rev, ",")
            |> list.try_map(int.parse)
        }
        Ok(user_clicked_code(list.reverse(rev)))
      }
      Error(Nil) -> Error(user_clicked_code([]))
    }
  })
}
