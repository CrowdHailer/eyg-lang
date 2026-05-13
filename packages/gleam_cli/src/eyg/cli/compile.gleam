import eyg/cli/internal/config
import eyg/cli/internal/source
import eyg/compiler
import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex

pub fn execute(
  file: String,
  _config: config.Config,
) -> promise.Promise(Result(Nil, String)) {
  use source <- promisex.try_sync(source.read(file))
  io.println(compiler.to_js(source, dict.new()))
  promise.resolve(Ok(Nil))
}
