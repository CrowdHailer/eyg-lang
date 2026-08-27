import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/source
import eyg/cli/internal/store
import eyg/cli/system
import eyg/hub/cache
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/option.{None, Some}

pub fn execute(
  package: String,
  file: String,
  config: config.Config,
) -> promise.Promise(Result(Int, String)) {
  let config.Config(client:, dirs:) = config
  // TODO list a readDirectory effect and list_files driver
  use signatories <- promisex.try_sync(store.all_signatories(dirs))
  use signatory <- promisex.try_sync(case signatories {
    [] -> Error("No signatories created.")
    [signatory] -> Ok(signatory)
    _ -> Error("Multiple signatories created")
  })
  {
    let input = source.File(file)
    use code <- system.then(source.read_input_effect(input))
    use code <- system.try(code)
    use source <- system.try(source.parse_input(code, source.File(file)))
    use module <- system.then(client.share_module(source, config.client))
    use module <- system.try(module)
    use index <- system.then(client.run_all(cache.pull(cache.empty())))
    use index <- system.try(case index.cursor_status {
      cache.PullFailed(reason) -> Error(reason)
      _ -> Ok(index)
    })
    let previous = case cache.package(index, package) {
      Ok(cache.Entry(sequence:, cid:, ..)) -> Some(#(sequence, cid))
      Error(Nil) -> None
    }
    use response <- system.then(client.submit_release(
      signatory,
      package,
      module,
      previous,
      client,
    ))
    use _response <- system.try(response)
    system.Done(Ok(0))
  }
  |> system.run
}
