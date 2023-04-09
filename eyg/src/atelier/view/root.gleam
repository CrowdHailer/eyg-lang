import gleam/io
import lustre/element.{div}
import lustre/attribute.{attribute, autofocus, class}
import lustre/event.{on_keydown}
import atelier/app
import atelier/view/projection
import atelier/view/pallet

// maybe belongs in procejection .render
pub fn render(state: app.WorkSpace) {
  div(
    [
      on_keydown(app.Keypress),
      attribute("tabIndex", "-1"),
      // autofocus attribute is not appearing on rendered element, is this because it's a div?
      // attribute("autoFocus", "100"),
      // autofocus(True),
      class("vstack"),
    ],
    [
      div([class("expand")], []),
      projection.render(state.source, state.selection, state.inferred),
      div([class("expand")], []),
      pallet.render(state, state.inferred),
    ],
  )
}
