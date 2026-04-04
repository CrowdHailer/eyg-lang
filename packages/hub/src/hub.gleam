import gleam/erlang/process
import gleam/io
import hub/app
import hub/config

pub fn main() -> Nil {
  start("production", fn(x) { x })
}

pub fn start(mode, reload) {
  io.println("Starting in " <> mode <> " mode.")
  let assert Ok(config) = config.from_env()
  let assert Ok(_) = app.start(config, reload)
  process.sleep_forever()
}
