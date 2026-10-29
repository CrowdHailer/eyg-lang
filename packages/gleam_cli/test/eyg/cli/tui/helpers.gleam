import etui/backend
import etui/buffer as etui_buffer
import etui/geometry
import eyg/cli/tui/state.{State}
import eyg/cli/tui/view
import eyg/hub/cache
import eyg/interpreter/builtin
import eyg/interpreter/state as istate
import eyg/parser/lexer
import eyg/parser/parser
import eyg/parser/token
import gleam/int
import gleam/list
import gleam/pair
import gleam/result
import gleam/string
import loam/execute
import morph/buffer
import ogre/origin

pub fn with_code(state, code) {
  let assert Ok(source) = block_from_string(code)
  with_source(state, source)
}

pub fn with_source(state, source) {
  State(
    ..state,
    buffer: buffer.from_source(
      source,
      state.repl_context(state.scope),
      cache.types(state.execute_state.cache),
    ),
  )
}

pub fn with_run(state, active, occured) {
  State(
    ..state,
    mode: state.Running(
      active:,
      env: builtin.default([]),
      k: istate.Empty,
      occured:,
    ),
  )
}

pub fn execute_state() {
  execute.State(origin.https("eyg.test"), cache.empty())
}

pub fn block_from_string(src) {
  src
  |> lexer.lex()
  |> token.drop_whitespace()
  |> token.drop_comments()
  |> parser.block()
  |> result.map(pair.first)
}

pub fn key(state, key) {
  state.update(state, state.Input(backend.KeyPress(key)))
}

/// The characters on screen, one trimmed row per line.
pub fn screen_text(state, width, height) {
  let screen = view.render(state, geometry.rect_new(0, 0, width, height))
  int.range(0, height, [], fn(rows, y) {
    let row =
      int.range(0, width, "", fn(acc, x) {
        acc
        <> etui_buffer.cell_symbol(etui_buffer.get_cell(
          screen,
          geometry.Position(x, y),
        ))
      })
    [string.trim_end(row), ..rows]
  })
  |> list.reverse
  |> string.join("\n")
}
