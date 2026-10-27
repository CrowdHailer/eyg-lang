import birdie
import etui/backend
import etui/buffer as terminal_buffer
import etui/geometry
import eyg/cli/tui/state.{State}
import eyg/cli/tui/view
import eyg/hub/cache
import eyg/interpreter/builtin
import eyg/interpreter/state as istate
import eyg/interpreter/value
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

pub fn multiple_error_test() {
  let state =
    state.init([], execute_state())
    |> with_code("let foo = todo let bar = unknown let baz = {}.foo")
  let #(state, _) = state.update(state.Input(backend.KeyPress(" ")), state)
  let buffer = view.render(state, screen())
  buffer_coloured_text(buffer)
  |> birdie.snap("multiple_error_test")
}

pub fn in_progress_effects_test() {
  let state =
    state.init([], execute_state())
    |> with_code("let x = perform Sleep(200) let x = perform Sleep(5000) 10")
    |> with_run(
      state.Handling(task_id: 1, label: "Sleep", lift: value.Integer(5000)),
      [#("Sleep", #(value.Integer(200), value.unit()))],
    )

  let #(state, _) = state.update(state.Input(backend.KeyPress(" ")), state)
  let buffer = view.render(state, screen())
  buffer_coloured_text(buffer)
  |> birdie.snap("in_progress_effects_test")
}

fn screen() {
  geometry.rect_new(0, 0, 80, 10)
}

fn with_code(state, code) {
  let assert Ok(source) = block_from_string(code)
  with_source(state, source)
}

fn with_source(state, source) {
  State(
    ..state,
    buffer: buffer.from_source(
      source,
      state.repl_context(state.scope),
      cache.types(state.execute_state.cache),
    ),
  )
}

fn with_run(state, active, occured) {
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

fn block_from_string(src) {
  src
  |> lexer.lex()
  |> token.drop_whitespace()
  |> token.drop_comments()
  |> parser.block()
  |> result.map(pair.first)
}

// fn buffer_text(buffer: terminal_buffer.Buffer) -> String {
//   let area = terminal_buffer.area(buffer)

//   list.repeat(Nil, area.size.height)
//   |> list.index_map(fn(_, row) {
//     list.repeat(Nil, area.size.width)
//     |> list.index_map(fn(_, col) {
//       let cell =
//         terminal_buffer.get_cell(
//           buffer,
//           geometry.Position(x: area.position.x + col, y: area.position.y + row),
//         )

//       case cell.content {
//         terminal_buffer.Content(symbol, _) -> symbol
//         terminal_buffer.Continuation -> ""
//       }
//     })
//     |> string.concat
//     |> string.trim_end
//   })
//   |> string.join("\n")
// }

fn buffer_coloured_text(buffer: terminal_buffer.Buffer) -> String {
  let area = terminal_buffer.area(buffer)

  let row_moves =
    list.repeat(Nil, area.size.height)
    |> list.index_map(fn(_, row) {
      let command =
        "\u{001B}["
        <> int.to_string(area.position.y + row + 1)
        <> ";"
        <> int.to_string(area.position.x + 1)
        <> "H"

      let replacement = case row {
        0 -> ""
        _ -> "\n"
      }

      #(command, replacement)
    })

  list.fold(row_moves, terminal_buffer.to_ansi(buffer), fn(text, move) {
    let #(command, replacement) = move
    string.replace(text, command, replacement)
  })
}
