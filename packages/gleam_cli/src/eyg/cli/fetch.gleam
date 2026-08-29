import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/system
import eyg/ir/dag_json
import multiformats/cid/v1

pub fn execute(
  cid: String,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use #(cid, _) <- system.try(v1.from_string(cid))
  use source <- system.then(client.get_module(cid, config.client))
  use source <- system.try(source)
  use Nil <- system.then(system.stdout(dag_json.to_string(source)))
  system.Done(Ok(0))
}
