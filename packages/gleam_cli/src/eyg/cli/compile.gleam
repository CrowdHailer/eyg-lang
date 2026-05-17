import eyg/cli/internal/config
import eyg/cli/internal/source
import eyg/compiler
import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex

pub fn execute(
  input: source.Input,
  _config: config.Config,
) -> promise.Promise(Result(Nil, String)) {
  use code <- promisex.try_sync(source.read_input(input))
  use source <- promisex.try_sync(source.parse_input(code, input))
  io.println(compiler.to_js(source, dict.new()))
  promise.resolve(Ok(Nil))
}
