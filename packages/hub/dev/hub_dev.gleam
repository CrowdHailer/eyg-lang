import argv
import gleam/int
import gleam/io
import hub
import hub/db/migrations
import mist/reload

pub fn main() {
  case argv.load().arguments {
    [] -> hub.start("development", reload.wrap)
    ["migrate"] -> {
      migrations.apply_all(todo)
    }
    ["rollback", count] -> {
      let assert Ok(count) = int.parse(count)
      migrations.rollback_n(todo, count)
      Nil
    }
    _ ->
      io.println(
        "Usage:
      gleam dev  
        [] - start sever with reload
        [migrate] - run all migrations
        [rollback N] - rollback N migrations
      ",
      )
  }
}
