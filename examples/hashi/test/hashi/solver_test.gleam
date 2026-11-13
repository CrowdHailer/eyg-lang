import gleam/list
import hashi/board
import hashi/play.{Run}
import simplifile

fn solve(seed) {
  let assert Ok(library) = simplifile.read("library.eyg")
  let assert Ok(solver) = simplifile.read("solver.eyg")
  let assert Ok(shell) = play.start(library)
  let Run(shell:, board:, ..) = play.run(shell, board.generate(seed), solver)
  let Run(board:, ..) = play.run(shell, board, "solve({})")
  board
}

pub fn the_solver_script_solves_a_board_the_numbers_force_test() {
  assert board.is_solved(solve(1))
}

pub fn the_solver_script_stops_when_nothing_is_forced_test() {
  let board = solve(2)
  assert !board.is_solved(board)
  assert board.bridges(board) != []
  assert list.any(board.islands(board), fn(island) {
    island.bridges < island.target
  })
}
