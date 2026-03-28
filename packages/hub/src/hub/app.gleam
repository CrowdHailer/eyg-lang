import gleam/otp/static_supervisor as supervisor
import hub/server

pub fn start(config, reload) {
  supervisor.new(supervisor.OneForOne)
  // |> supervisor.add(database_pool.supervised(config))
  |> supervisor.add(server.supervised(config, reload))
  |> supervisor.start
}
