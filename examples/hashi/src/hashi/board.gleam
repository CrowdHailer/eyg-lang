//// The game, driven through nothing but the public API of the original
//// project. A bridge is added the way a player adds one, by pressing on one
//// island and then the other.

import frontend/hashi_grid
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import hashi/effect.{type Bridge, type Island, type Point, type Refusal}
import shared/hashi

pub type Board {
  Board(puzzle: hashi.Puzzle, grid: hashi_grid.Model)
}

pub fn new(puzzle: hashi.Puzzle) -> Board {
  let grid =
    hashi_grid.init(hashi_grid.InitState(puzzle:, connections: dict.new()))
  Board(puzzle:, grid:)
}

/// A puzzle the same size as the daily puzzle, generated from a seed.
pub fn generate(seed: Int) -> Board {
  hashi.new(width: 7, height: 7, islands: 12)
  |> hashi.with_seed(seed)
  |> hashi.generate
  |> new
}

pub fn islands(board: Board) -> List(Island) {
  let Board(puzzle:, grid:) = board
  let connections = hashi_grid.current_solution(grid).connections
  let cells = {
    use cells, y <- int.range(hashi.height(puzzle) - 1, -1, [])
    use cells, x <- int.range(hashi.width(puzzle) - 1, -1, cells)
    [#(x, y), ..cells]
  }
  use #(x, y) <- list.filter_map(cells)
  use target <- result.map(hashi.island_rank(puzzle, #(x, y)))
  let bridges =
    dict.get(connections, #(x, y))
    |> result.unwrap(dict.new())
    |> dict.fold(0, fn(total, _, bridge) { total + count(bridge) })
  effect.Island(at: #(x, y), target:, bridges:)
}

/// Every bridge once, from the island that sorts first.
pub fn bridges(board: Board) -> List(Bridge) {
  let connections = hashi_grid.current_solution(board.grid).connections
  use #(from, others) <- list.flat_map(dict.to_list(connections))
  use #(to, bridge) <- list.filter_map(dict.to_list(others))
  case before(from, to) {
    True -> Ok(effect.Bridge(from:, to:, count: count(bridge)))
    False -> Error(Nil)
  }
}

fn count(bridge) {
  case bridge {
    hashi.Single -> 1
    hashi.Double -> 2
  }
}

fn bridge_between(board: Board, from: Point, to: Point) {
  hashi_grid.current_solution(board.grid).connections
  |> dict.get(from)
  |> result.try(dict.get(_, to))
}

pub fn add_bridge(board: Board, from: Point, to: Point) {
  use <- check_move(board, from, to)
  case bridge_between(board, from, to) {
    Ok(hashi.Double) -> Error(effect.Full)
    _ -> {
      let before = hashi_grid.current_solution(board.grid)
      let board = press(board, from) |> press(to)
      case hashi_grid.current_solution(board.grid) == before {
        // The second press found no bridge to build and selected `to` as the
        // start of a new one, that board is thrown away.
        True -> Error(effect.NotReachable)
        False -> Ok(board)
      }
    }
  }
}

pub fn remove_bridge(board: Board, from: Point, to: Point) {
  use <- check_move(board, from, to)
  case bridge_between(board, from, to) {
    Ok(_) ->
      Ok(send(board, hashi_grid.UserClickedBridge(between: from, and: to)))
    Error(Nil) -> Error(effect.NoBridge)
  }
}

fn check_move(board: Board, from, to, then) -> Result(Board, Refusal) {
  case
    hashi_grid.is_complete(board.grid),
    hashi.has_island(board.puzzle, from),
    hashi.has_island(board.puzzle, to)
  {
    True, _, _ -> Error(effect.AlreadySolved)
    _, False, _ -> Error(effect.NoIsland(from))
    _, _, False -> Error(effect.NoIsland(to))
    _, True, True -> then()
  }
}

fn press(board: Board, island: Point) {
  send(board, hashi_grid.UserPressedOnIsland(island:, pointer: #(0, 0)))
}

fn send(board: Board, message) {
  let #(grid, _effect) = hashi_grid.update(board.grid, message)
  Board(..board, grid:)
}

pub fn undo(board: Board) -> #(Board, Bool) {
  case hashi_grid.can_step_back(board.grid) {
    True -> #(Board(..board, grid: hashi_grid.step_back(board.grid)), True)
    False -> #(board, False)
  }
}

pub fn redo(board: Board) -> #(Board, Bool) {
  case hashi_grid.can_step_forward(board.grid) {
    True -> #(Board(..board, grid: hashi_grid.step_forward(board.grid)), True)
    False -> #(board, False)
  }
}

pub fn is_solved(board: Board) -> Bool {
  hashi_grid.is_complete(board.grid)
}

fn before(a: Point, b: Point) {
  let #(ax, ay) = a
  let #(bx, by) = b
  ax < bx || { ax == bx && ay < by }
}
