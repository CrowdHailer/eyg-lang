import gleam/io
import gleam/option
import lustre/element.{div}
import lustre/attribute.{attribute, autofocus, class}
import lustre/event.{on_keydown}
import eyg/incremental/source
import atelier/app
import atelier/view/projection
import atelier/view/pallet

// maybe belongs in procejection .render
pub fn render(state: app.WorkSpace) {
  let assert Ok(tree) = source.to_tree(state.source, state.root)
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
      // pass through inferred
      projection.render(tree, state.selection, option.None),
      div([class("expand")], []),
      pallet.render(state),
    ],
  )
}
