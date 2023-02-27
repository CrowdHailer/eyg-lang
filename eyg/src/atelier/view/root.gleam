import lustre/element.{div}
import lustre/attribute.{class}
import atelier/app
import atelier/view/projection
import atelier/view/pallet

// maybe belongs in procejection .render
pub fn render(state: app.WorkSpace) {
  div(
    [class("h-screen vstack")],
    [
      div([class("spacer")], []),
      projection.render(state.source, state.selection, state.inferred),
      div([class("spacer")], []),
      pallet.render(state, state.inferred),
    ],
  )
}
