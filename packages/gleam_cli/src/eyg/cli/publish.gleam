import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/store
import eyg/cli/share
import eyg/hub/cache
import gleam/int
import gleam/option.{None, Some}
import loam/source
import loam/system
import multiformats/cid/v1

pub fn execute(
  package: String,
  file: String,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  let config.Config(client:, dirs:) = config
  use signatories <- system.then(store.all_signatories(dirs))
  use signatories <- system.try(signatories)
  use signatory <- system.try(case signatories {
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
  use module <- system.then(share.upload(source.File(file), config))
  use module <- system.try(module)
  use index <- system.then(client.run_all(cache.pull(cache.empty()), client))
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
