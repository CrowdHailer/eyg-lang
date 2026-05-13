import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/source
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/javascript/promisex
import multiformats/cid/v1

pub fn execute(
  file: String,
  config: config.Config,
) -> Promise(Result(Nil, String)) {
  use source <- promisex.try_sync(source.read(file))
  use cid <- promise.try_await(client.share_module(source, config.client))
  io.println(v1.to_string(cid))
  promise.resolve(Ok(Nil))
}
