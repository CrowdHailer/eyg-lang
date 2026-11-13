import etui/backend
import etui/buffer as screen_buffer
import etui/geometry
import eyg/cli/tui/state
import eyg/cli/tui/view
import eyg/hub/cache
import eyg/parser/lexer
import eyg/parser/parser
import eyg/parser/token
import gleam/option.{None}
import gleam/string
import loam/execute
import morph/buffer
import ogre/origin

pub fn same_structural_editor_evaluates_and_renders_on_the_beam_test() {
  let current =
    state.init(
      [],
      execute.State(origin.https("unused.invalid"), cache.ready(), None),
    )
  let assert Ok(#(source, _)) =
    lexer.lex("!int_add(20, 22)")
    |> token.drop_whitespace
    |> token.drop_comments
    |> parser.block
  let current =
    state.State(
      ..current,
      buffer: buffer.from_source(source)
        |> buffer.check(state.repl_context([]))
        |> cache.infer_sync(current.execute_state.cache),
    )
  let #(current, _) =
    state.update(current, state.Input(backend.KeyPress("enter")))
  assert !current.quit
  assert current.history != []
  let ansi =
    view.render(current, geometry.rect_new(0, 0, 100, 30))
    |> screen_buffer.to_ansi
  assert string.contains(ansi, "42")
}
