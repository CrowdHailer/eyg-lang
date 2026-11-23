import cloud/app
import cloud/config
import cloud/old
import gleam/erlang/process
import gleam/io

pub fn main() -> Nil {
  start("production")
}

pub fn start(mode) {
  io.println("Starting in " <> mode <> " mode.")
  let assert Ok(config) = config.from_env()
  let #(state, llm) = app.setup(config.bucket)
  let context = app.start(config, state, llm)
  old.start(context, state, llm)
  process.sleep_forever()
}
