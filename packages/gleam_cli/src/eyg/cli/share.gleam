import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/source
import eyg/cli/system
import multiformats/cid/v1

pub fn execute(
  input: source.Input,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use code <- system.then(source.read_input_effect(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))
  use cid <- system.then(client.share_module(source, config.client))
  use cid <- system.try(cid)
  use Nil <- system.then(system.stdout(v1.to_string(cid)))
  system.Done(Ok(0))
}
