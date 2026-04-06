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
      migrations.apply_all(db_config())
    }
    ["rollback", count] -> {
      let assert Ok(count) = int.parse(count)
      migrations.rollback_n(db_config(), count)
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

fn db_config() {
  let assert Ok(config) = config.from_env()
  let assert Ok(started) =
    pool.start(process.new_name("db_pool"), config.postgres)
  started.data
}
