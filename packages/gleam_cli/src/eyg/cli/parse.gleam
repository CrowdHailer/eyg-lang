import eyg/cli/internal/config
import eyg/ir/dag_json
import gleam/json
import loam/source as source_io
import loam/system
import touch_grass/source

pub fn execute(
  input: source.Input,
  _config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use code <- system.then(source_io.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))
  use Nil <- system.then(
    system.stdout(json.to_string(dag_json.to_data_model(source))),
  )
  system.Done(Ok(0))
}
