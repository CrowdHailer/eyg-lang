import birdie
import etui/backend
import etui/buffer as terminal_buffer
import etui/geometry
import eyg/cli/tui/helpers as h
import eyg/cli/tui/state
import eyg/cli/tui/view
import eyg/hub/cache
import eyg/interpreter/value
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import loam/execute
import loam/system
import multiformats/cid/v1

pub fn inserted_module_before_loading_test() {
  let assert Ok(#(cid, <<>>)) =
    v1.from_string(
      "baguqeera2rxu3p44bxjutnjlpeffcmkgdmh5mmyeqgpatyaae6ezybzg4azq",
    )
  // Startup has fetched the release metadata, but not its module.
  let cache =
    cache.Cache(
      ..cache.empty(),
      packages: dict.from_list([
        #(
          "demo",
          cache.Entry(version: 1, module: cid, cursor: 1, sequence: 1, cid:),
        ),
      ]),
      releases: dict.from_list([#(#("demo", 1), cid)]),
    )
  let state = state.init([], execute.State(..h.execute_state(), cache:))
  let assert #(state, []) =
    state.update(state, state.Input(backend.KeyPress("@")))
  let assert #(state, []) =
    state.update(state, state.Input(backend.KeyPress("tab")))
  let #(state, effects) =
    state.update(state, state.Input(backend.KeyPress("enter")))
  let assert [system.Fetch(_, _)] = effects
  assert state.Navigating == state.mode
  assert Error(cache.Requested)
    == cache.get_module(state.execute_state.cache, cid)

  view.render(state, screen())
  |> buffer_coloured_text
  |> birdie.snap("inserted_module_before_loading_test")
}

pub fn multiple_error_test() {
  let #(state, _) =
    state.init([], h.execute_state())
    |> h.with_code("let foo = todo let bar = unknown let baz = {}.foo")
    |> state.update(state.Input(backend.KeyPress(" ")))
  let buffer = view.render(state, screen())
  buffer_coloured_text(buffer)
  |> birdie.snap("multiple_error_test")
}

pub fn in_progress_effects_test() {
  let #(state, _) =
    state.init([], h.execute_state())
    |> h.with_code("let x = perform Sleep(200) let x = perform Sleep(5000) 10")
    |> h.with_run(
      state.Handling(task_id: 1, label: "Sleep", lift: value.Integer(5000)),
      [#("Sleep", #(value.Integer(200), value.unit()))],
    )
    |> state.update(state.Input(backend.KeyPress(" ")))

  let buffer = view.render(state, screen())
  buffer_coloured_text(buffer)
  |> birdie.snap("in_progress_effects_test")
}

fn screen() {
  geometry.rect_new(0, 0, 80, 10)
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
