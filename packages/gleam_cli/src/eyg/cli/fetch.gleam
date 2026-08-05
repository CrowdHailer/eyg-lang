import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/ir/dag_json
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import multiformats/cid/v1

pub fn execute(
  cid: String,
  config: config.Config,
) -> promise.Promise(Result(Int, String)) {
  use #(cid, _) <- promisex.try_sync(v1.from_string(cid))
  use source <- promise.try_await(client.get_module(cid, config.client))
  io.println(dag_json.to_string(source))
  promise.resolve(Ok(0))
}
