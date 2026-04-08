import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/source
import gleam/javascript/promise
import gleam/javascript/promisex
import multiformats/cid/v1

pub fn execute(file, config: config.Config) {
  use source <- promisex.try_sync(source.read(file))
  use cid <- promise.try_await(client.share_module(source, config.client))
  promise.resolve(Ok(v1.to_string(cid)))
}
