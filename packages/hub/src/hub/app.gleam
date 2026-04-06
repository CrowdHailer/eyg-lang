import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import hub/config
import hub/db/pool
import hub/server
import pog

pub fn start(config: config.Config, reload) {
  let pool_name = process.new_name("db_pool")
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(pool.supervised(pool_name, config.postgres))
  |> supervisor.add(server.supervised(
    config,
    pog.named_connection(pool_name),
    reload,
  ))
  |> supervisor.start
}
