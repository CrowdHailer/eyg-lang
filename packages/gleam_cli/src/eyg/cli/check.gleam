import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/cli/internal/config
import eyg/cli/internal/source
import eyg/parser
import gleam/javascript/promise.{type Promise}
import gleam/javascript/promisex

pub fn execute(
  input: source.Input,
  _config: config.Config,
) -> Promise(Result(Nil, String)) {
  use code <- promisex.try_sync(source.read_input(input))
  use source <- promisex.try_sync(source.parse(code))

  let context = infer.unpure()
  let analysis = infer.check(context, source)
  let errors = infer.all_errors(analysis)

  case errors {
    [] -> promise.resolve(Ok(Nil))
    [#(span, reason), ..] -> {
      let message = debug.render_reason(reason)
      let hint = debug.hint(reason)
      Error(parser.render_error(message, hint, code, span))
      |> promise.resolve
    }
  }
}
