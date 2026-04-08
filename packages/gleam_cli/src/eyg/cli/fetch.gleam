import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/ir/dag_json
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/option.{None, Some}
import multiformats/cid/v1

pub fn execute(cid, config: config.Config) {
  use #(cid, _) <- promisex.try_sync(v1.from_string(cid))
  use source <- promise.try_await(client.get_module(cid, config.client))
  case source {
    Some(source) -> promise.resolve(Ok(dag_json.to_string(source)))
    None -> promise.resolve(Error("unknown module"))
  }
}
