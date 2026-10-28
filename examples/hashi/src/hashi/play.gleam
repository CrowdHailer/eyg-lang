//// Play the game by running EYG, in a shell from `eyg_embed` whose only
//// effects are the game's. Everything here is about the game, the shell
//// does the parsing, checking, running and keeping variables.

import eyg/embed/shell.{type Shell}
import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/list
import hashi/board.{type Board}
import hashi/effect

pub type Run {
  Run(shell: Shell, board: Board, printed: List(String), outcome: shell.Outcome)
}

/// A shell with the game's effects and the library in scope as `hashi`.
pub fn start(library: String) -> Result(Shell, String) {
  shell.new(effect.types()) |> shell.with_module("hashi", library)
}

pub fn run(shell: Shell, board: Board, code: String) -> Run {
  let shell.Run(shell:, state: #(board, printed), outcome:) =
    shell.run(shell, code, #(board, []), handle)
  Run(shell:, board:, printed: list.reverse(printed), outcome:)
}

/// What a person, or the agent, is told about a run.
pub fn report(run: Run) -> String {
  shell.report(run.printed, run.outcome)
}

fn handle(game, label, lift) {
  let #(board, printed) = game
  case effect.cast(label, lift) {
    Ok(effect.Print(line)) -> Ok(#(#(board, [line, ..printed]), v.unit()))
    Ok(request) -> {
      let #(board, reply) = answer(board, request)
      Ok(#(#(board, printed), reply))
    }
    Error(_) -> Error("not a " <> label)
  }
}

/// Answer one effect, all of them are synchronous.
pub fn answer(
  board: Board,
  request: effect.Effect,
) -> #(Board, state.Value(m)) {
  case request {
    effect.ListIslands -> #(board, effect.islands(board.islands(board)))
    effect.ListBridges -> #(board, effect.bridges(board.bridges(board)))
    effect.AddBridge(from:, to:) ->
      settle(board, board.add_bridge(board, from, to))
    effect.RemoveBridge(from:, to:) ->
      settle(board, board.remove_bridge(board, from, to))
    effect.Undo -> {
      let #(board, moved) = board.undo(board)
      #(board, v.bool(moved))
    }
    effect.Redo -> {
      let #(board, moved) = board.redo(board)
      #(board, v.bool(moved))
    }
    effect.IsSolved -> #(board, v.bool(board.is_solved(board)))
    effect.Print(_) -> #(board, v.unit())
  }
}

fn settle(board, result) {
  case result {
    Ok(board) -> #(board, effect.outcome(Ok(Nil)))
    Error(refusal) -> #(board, effect.outcome(Error(refusal)))
  }
}
