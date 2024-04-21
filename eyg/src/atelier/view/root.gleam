import atelier/app
import atelier/view/pallet
import atelier/view/projection
import lustre/attribute.{class}
import lustre/element/html.{div}

pub fn render(state: app.WorkSpace) {
  div([class("vstack")], [
    div([class("expand")], []),
    projection.render(state.source, state.selection, state.inferred),
    div([class("expand")], []),
    pallet.render(state, state.inferred),
  ])
}
