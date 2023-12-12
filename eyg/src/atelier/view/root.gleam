import lustre/element/html.{div}
import lustre/attribute.{class}
import atelier/app
import atelier/view/projection
import atelier/view/pallet

pub fn render(state: app.WorkSpace) {
  div([class("vstack")], [
    div([class("expand")], []),
    projection.render(state.source, state.selection, state.inferred),
    div([class("expand")], []),
    pallet.render(state, state.inferred),
  ])
}
