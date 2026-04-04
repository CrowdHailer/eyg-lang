import eyg/cli/internal/client
import eyg/ir/dag_json
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/option.{None, Some}
import multiformats/cid/v1

pub fn execute(cid, config) {
  use #(cid, _) <- promisex.try_sync(v1.from_string(cid))
  use source <- promise.try_await(client.get_module(cid, config))
  case source {
    Some(source) -> promise.resolve(Ok(dag_json.to_string(source)))
    None -> promise.resolve(Error("unknown module"))
  }
}
