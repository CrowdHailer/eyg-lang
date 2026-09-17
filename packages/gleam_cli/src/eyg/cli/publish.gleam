import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/source
import eyg/cli/internal/store
import eyg/cli/system
import eyg/hub/cache
import gleam/int
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/option.{None, Some}
import multiformats/cid/v1

pub fn execute(
  package: String,
  file: String,
  config: config.Config,
) -> promise.Promise(Result(Int, String)) {
  let config.Config(client:, dirs:) = config
  // TODO list a readDirectory effect and list_files driver
  use signatories <- promisex.try_sync(store.all_signatories(dirs))
  use signatory <- promisex.try_sync(case signatories {
    [] ->
      Error(
        "No signatories created. Run 'eyg signatory initial <alias>', then ask a hub administrator to grant it ownership of package '"
        <> package
        <> "'.",
      )
    [signatory] -> Ok(signatory)
    _ ->
      Error(
        "Multiple signatories created; publishing requires exactly one local signatory. Run 'eyg signatory list' to inspect them.",
      )
  })
  {
    let input = source.File(file)
    use code <- system.then(source.read_input(input))
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
    use response <- system.try(response)
    use Nil <- system.then(system.stdout(
      "Published @"
      <> package
      <> ":"
      <> int.to_string(response.sequence)
      <> ":"
      <> v1.to_string(module),
    ))
    system.Done(Ok(0))
  }
  |> system.run
}
