import eyg/cli/tui/state.{State}
import eyg/hub/cache
import eyg/interpreter/builtin
import eyg/interpreter/state as istate
import eyg/parser/lexer
import eyg/parser/parser
import eyg/parser/token
import gleam/pair
import gleam/result
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
