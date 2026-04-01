import argv
import gleam/erlang/process
import gleam/int
import gleam/io
import hub
import hub/config
import hub/db/migrations
import hub/db/pool
import mist/reload

pub fn main() {
  case argv.load().arguments {
    [] -> hub.start("development", reload.wrap)
    ["migrate"] -> {
      let assert Ok(config) = config.from_env()
      let assert Ok(started) =
        pool.start(process.new_name("db_pool"), config.postgres_password)
      migrations.apply_all(started.data)
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
