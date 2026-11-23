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
  let #(state, _llm) = app.setup(config.bucket)
  let assert Ok(_) = app.start(config, state)
  process.sleep_forever()
}
