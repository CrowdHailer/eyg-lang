import eyg/editor/v1/app
import eyg/editor/v1/view/pallet
import eyg/editor/v1/view/projection
import lustre/attribute.{class}
import lustre/element/html.{div}

pub fn render(state: app.WorkSpace) {
  div([class("vstack h-screen")], [
    div([class("expand")], []),
    projection.render(state.source, state.selection, state.inferred),
    div([class("expand")], []),
    pallet.render(state, state.inferred),
  ])
}
