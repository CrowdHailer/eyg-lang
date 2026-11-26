import cloud/app
import cloud/config
import gleam/erlang/process
import gleam/io

pub fn main() -> Nil {
  start("production")
}

pub fn start(mode) {
  io.println("Starting in " <> mode <> " mode.")
  let assert Ok(config) = config.from_env()
  let assert Ok(_) = app.start(config)
  process.sleep_forever()
}
