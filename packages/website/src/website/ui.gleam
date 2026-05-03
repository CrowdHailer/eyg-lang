import eyg/analysis/inference/levels_j/contextual as infer
import gleam/dynamic/decode
import gleam/dynamicx
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/lustre/frame
import morph/lustre/highlight
import morph/lustre/render
import morph/projection as p
import plinth/browser/element as pelement
import plinth/browser/event as pevent

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
