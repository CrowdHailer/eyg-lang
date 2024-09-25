import eyg/analysis/inference/levels_j/contextual as j
import eyg/runtime/break
import eyg/shell/examples
import eyg/shell/state
import eyg/sync/sync
import gleam/dict
import gleam/dynamic
import gleam/dynamicx
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import lustre/element.{text}
import lustre/element/html as h
import morph/analysis
import spotless/state as old_state
import spotless/view/page

pub fn render(state) {
  let state.Shell(
    situation: _,
    cache: cache,
    previous: previous,
    scope: scope,
    buffer: buffer,
    runner: running,
  ) = state
  h.div([], [
    text("Yo"),
    h.div([], [
      case scope {
        None -> text("Not ready")
        Some(_) -> text("scope is ready")
      },
    ]),
    h.input([]),
    h.div(
      [],
      // TODO real ref lookup
      list.map(sync.missing(cache, []), fn(h) { h.div([], [text(h)]) }),
    ),
  ])
  let executing = case running {
    Some(state.Run(state.Failed(debug), _effects)) ->
      old_state.Failed(break.reason_to_string(debug.0))
    Some(state.Run(_, effects)) -> {
      io.debug(effects)
      old_state.Running
    }
    None -> old_state.Editing(buffer.1)
  }
  let tenv = case scope {
    Some(#(_env, tenv)) -> tenv
    None -> []
  }
  let context =
    analysis.Context(
      // bindings are empty as long as everything is properly poly
      bindings: dict.new(),
      scope: tenv,
      references: sync.types(cache),
      builtins: j.builtins(),
    )
  page.do_render(
    dynamicx.unsafe_coerce(dynamic.from(previous)),
    context,
    state.buffer.0,
    executing,
    examples.examples(),
    state.Buffer,
    fn() { state.Interrupt },
    state.Selected,
  )
}
