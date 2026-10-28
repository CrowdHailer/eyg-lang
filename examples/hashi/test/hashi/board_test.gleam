import hashi/board
import hashi/effect.{Bridge, Island}
import hashi/fixture

pub fn islands_are_listed_in_reading_order_test() {
  assert board.islands(fixture.corners())
    == [
      Island(at: #(0, 0), target: 2, bridges: 0),
      Island(at: #(2, 0), target: 3, bridges: 0),
      Island(at: #(0, 2), target: 1, bridges: 0),
      Island(at: #(2, 2), target: 2, bridges: 0),
    ]
}

pub fn a_bridge_joins_two_islands_in_line_test() {
  let assert Ok(board) = board.add_bridge(fixture.corners(), #(0, 0), #(2, 0))
  assert board.bridges(board) == [Bridge(from: #(0, 0), to: #(2, 0), count: 1)]
}

pub fn a_second_bridge_makes_a_double_and_a_third_is_refused_test() {
  let assert Ok(board) = board.add_bridge(fixture.corners(), #(0, 0), #(2, 0))
  let assert Ok(board) = board.add_bridge(board, #(2, 0), #(0, 0))
  assert board.bridges(board) == [Bridge(from: #(0, 0), to: #(2, 0), count: 2)]
  assert board.add_bridge(board, #(0, 0), #(2, 0)) == Error(effect.Full)
}

pub fn islands_out_of_line_are_not_reachable_test() {
  assert board.add_bridge(fixture.corners(), #(0, 0), #(2, 2))
    == Error(effect.NotReachable)
}

pub fn an_island_cannot_bridge_to_itself_test() {
  assert board.add_bridge(fixture.corners(), #(0, 0), #(0, 0))
    == Error(effect.NotReachable)
}

pub fn a_bridge_needs_an_island_at_both_ends_test() {
  assert board.add_bridge(fixture.corners(), #(1, 1), #(2, 1))
    == Error(effect.NoIsland(#(1, 1)))
  assert board.add_bridge(fixture.corners(), #(0, 0), #(1, 0))
    == Error(effect.NoIsland(#(1, 0)))
}

pub fn bridges_cannot_cross_test() {
  let assert Ok(board) = board.add_bridge(fixture.cross(), #(1, 0), #(1, 2))
  assert board.add_bridge(board, #(0, 1), #(2, 1)) == Error(effect.NotReachable)
}

pub fn a_refused_bridge_leaves_nothing_selected_test() {
  let assert Error(_) = board.add_bridge(fixture.corners(), #(0, 0), #(2, 2))
  let assert Ok(board) = board.add_bridge(fixture.corners(), #(0, 2), #(2, 2))
  assert board.bridges(board) == [Bridge(from: #(0, 2), to: #(2, 2), count: 1)]
}

pub fn removing_takes_away_one_bridge_test() {
  let assert Ok(board) = board.add_bridge(fixture.corners(), #(0, 0), #(2, 0))
  let assert Ok(board) = board.remove_bridge(board, #(2, 0), #(0, 0))
  assert board.bridges(board) == []
  assert board.remove_bridge(board, #(0, 0), #(2, 0)) == Error(effect.NoBridge)
}

pub fn undo_and_redo_step_through_history_test() {
  let empty = fixture.corners()
  let assert #(_, False) = board.undo(empty)
  let assert Ok(one) = board.add_bridge(empty, #(0, 0), #(2, 0))
  let assert #(back, True) = board.undo(one)
  assert board.bridges(back) == []
  let assert #(forward, True) = board.redo(back)
  assert board.bridges(forward) == board.bridges(one)
  let assert #(_, False) = board.redo(forward)
}

pub fn a_solved_board_refuses_moves_test() {
  let board = solve(fixture.corners())
  assert board.is_solved(board)
  assert board.add_bridge(board, #(0, 2), #(0, 0))
    == Error(effect.AlreadySolved)
}

fn solve(board) {
  let assert Ok(board) = board.add_bridge(board, #(0, 0), #(2, 0))
  let assert Ok(board) = board.add_bridge(board, #(0, 0), #(2, 0))
  let assert Ok(board) = board.add_bridge(board, #(2, 0), #(2, 2))
  let assert False = board.is_solved(board)
  let assert Ok(board) = board.add_bridge(board, #(2, 2), #(0, 2))
  board
}
