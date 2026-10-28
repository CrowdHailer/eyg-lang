import eyg/embed/shell.{Returned}
import eyg/interpreter/value as v
import gleam/dict
import gleam/option.{None, Some}
import hashi/board
import hashi/effect.{Bridge}
import hashi/fixture
import hashi/play.{Run}
import simplifile

fn shell() {
  let assert Ok(library) = simplifile.read("library.eyg")
  let assert Ok(shell) = play.start(library)
  shell
}

fn value(code) {
  let assert Run(outcome: Returned(Some(value)), ..) =
    play.run(shell(), fixture.corners(), code)
  value
}

pub fn a_run_returns_its_last_expression_test() {
  assert value("!int_add(1, 2)") == v.Integer(3)
}

pub fn variables_are_kept_for_the_next_run_test() {
  let assert Run(shell:, board:, outcome: Returned(None), ..) =
    play.run(shell(), fixture.corners(), "let a = 5\nlet f = (x) -> { x }")
  let assert Run(outcome: Returned(Some(value)), ..) =
    play.run(shell, board, "!int_add(f(a), 1)")
  assert value == v.Integer(6)
}

pub fn a_kept_function_is_still_generic_test() {
  let Run(shell:, board:, ..) =
    play.run(shell(), fixture.corners(), "let id = (x) -> { x }")
  let assert Run(outcome: Returned(Some(value)), ..) =
    play.run(shell, board, "let _ = id(\"s\")\nid(2)")
  assert value == v.Integer(2)
}

pub fn a_type_error_stops_the_program_before_it_runs_test() {
  let assert Run(board:, outcome: shell.TypeFailed([_]), ..) =
    play.run(
      shell(),
      fixture.corners(),
      "let _ = perform AddBridge({from: {x: 0, y: 0}, to: {x: 2, y: 0}})\n!int_add(1, \"two\")",
    )
  assert board.bridges(board) == []
}

pub fn an_effect_the_game_does_not_have_is_a_type_error_test() {
  let assert Run(outcome: shell.TypeFailed([_]), ..) =
    play.run(shell(), fixture.corners(), "perform Fetch({})")
}

pub fn a_parse_error_is_reported_test() {
  let assert Run(outcome: shell.ParseFailed(_), ..) =
    play.run(shell(), fixture.corners(), "let = ")
}

pub fn effects_change_the_board_test() {
  let assert Run(board:, outcome: Returned(Some(value)), ..) =
    play.run(
      shell(),
      fixture.corners(),
      "perform AddBridge({from: {x: 0, y: 0}, to: {x: 2, y: 0}})",
    )
  assert value == v.ok(v.unit())
  assert board.bridges(board) == [Bridge(from: #(0, 0), to: #(2, 0), count: 1)]
}

pub fn refusals_are_returned_to_the_program_test() {
  assert value("perform AddBridge({from: {x: 1, y: 1}, to: {x: 2, y: 0}})")
    == v.error(v.Tagged("NoIsland", point(1, 1)))
}

pub fn printed_lines_are_collected_test() {
  let Run(printed:, ..) =
    play.run(
      shell(),
      fixture.corners(),
      "let _ = perform Print(\"a\")\nlet _ = perform Print(\"b\")\n{}",
    )
  assert printed == ["a", "b"]
}

pub fn the_library_finds_neighbours_test() {
  let assert v.LinkedList(neighbours) =
    value(
      "let corner = {x: 0, y: 0, target: 2, bridges: 0}\nhashi.map(hashi.neighbours(corner), (island) -> { island.target })",
    )
  assert neighbours == [v.Integer(1), v.Integer(3)]
}

pub fn the_library_can_solve_the_corners_test() {
  let assert Run(board:, outcome: Returned(Some(value)), ..) =
    play.run(
      shell(),
      fixture.corners(),
      "let {connect, with_target} = hashi
let top_left = {x: 0, y: 0}
let top_right = {x: 2, y: 0}
let _ = connect(top_left, top_right)
let _ = connect(top_left, top_right)
let _ = connect(top_right, {x: 2, y: 2})
let _ = hashi.each(with_target(1), (island) -> { connect(island, {x: 2, y: 2}) })
perform IsSolved({})",
    )
  assert value == v.true()
  assert board.is_solved(board)
}

fn point(x, y) {
  v.Record(dict.from_list([#("x", v.Integer(x)), #("y", v.Integer(y))]))
}

pub fn an_effect_inside_a_library_function_keeps_the_shell_scope_test() {
  let Run(shell:, board:, ..) =
    play.run(shell(), fixture.corners(), "let before = 1\nhashi.islands({})")
  let assert Run(outcome: Returned(Some(value)), ..) =
    play.run(shell, board, "let _ = hashi.islands({})\nbefore")
  assert value == v.Integer(1)
}

pub fn a_misspelt_field_is_refused_before_anything_runs_test() {
  let assert Run(board:, outcome: shell.TypeFailed(reasons), ..) =
    play.run(
      shell(),
      fixture.corners(),
      "let _ = hashi.connect({x: 0, y: 0}, {x: 2, y: 0})\nperform AddBridge({form: {x: 0, y: 0}, to: {x: 2, y: 0}})",
    )
  assert reasons == ["line 2: missing row 'form'"]
  assert board.bridges(board) == []
}
