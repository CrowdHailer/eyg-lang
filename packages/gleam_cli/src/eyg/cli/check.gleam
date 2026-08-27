import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/cli/internal/config
import eyg/cli/internal/source
import eyg/cli/system
import eyg/parser
import gleam/dict

pub fn execute(
  input: source.Input,
  _config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use code <- system.then(source.read_input_effect(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))

  let context = infer.unpure()
  // TODO follow all references
  let analysis = infer.check_with_references(context, dict.new(), source)
  let errors = infer.all_errors(analysis)

  case errors {
    [] -> {
      use Nil <- system.then(
        system.stdout(debug.render_type(infer.type_(analysis))),
      )
      system.Done(Ok(0))
    }
    [#(location, reason), ..] -> {
      let message = debug.render_reason(reason)
      let hint = debug.hint(reason)
      Error(parser.render_error(message, hint, code, source.span(location)))
      |> system.Done
    }
  }
}
