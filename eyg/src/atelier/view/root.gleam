import gleam/dynamic
import gleam/string
import gleam/io
import gleam/list
import gleam/map
import gleam/result
import gleam/option.{None, Some}
import lustre/element.{button, div, input, p, pre, span, text}
import lustre/event.{dispatch, on_click, on_keydown}
import lustre/attribute.{class, classes}
import atelier/app.{ClickOption, SelectNode}
import atelier/view/projection
import atelier/view/pallet
import eyg/runtime/standard

// maybe belongs in procejection .render
pub fn render(state: app.WorkSpace) {
  let inferred = standard.infer(state.source)

  div(
    [class("h-screen vstack")],
    [
      div([class("spacer")], []),
      projection.render(state.source, state.selection, inferred),
      div([class("spacer")], []),
      pallet.render(state, inferred),
    ],
  )
}
